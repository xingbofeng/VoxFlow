import AppKit
import Foundation

protocol AgentRuntimeServing: Sendable {
    func availability(forceRefresh: Bool) async -> AgentRuntimeAvailability
    func availability(forceRefresh: Bool, providerID: String) async -> AgentRuntimeAvailability
    func runIfAvailable(
        taskID: String,
        instruction: String,
        context: ContextSnapshot?,
        target: DictationTarget?,
        model: String?,
        onEvent: @escaping @Sendable (AgentActionEvent) -> Void
    ) async throws -> AgentRuntimeServiceResult
    func runIfAvailable(
        taskID: String,
        instruction: String,
        context: ContextSnapshot?,
        target: DictationTarget?,
        providerID: String,
        model: String?,
        onEvent: @escaping @Sendable (AgentActionEvent) -> Void
    ) async throws -> AgentRuntimeServiceResult
}

extension AgentRuntimeServing {
    func availability(forceRefresh: Bool, providerID: String) async -> AgentRuntimeAvailability {
        await availability(forceRefresh: forceRefresh)
    }

    func runIfAvailable(
        taskID: String,
        instruction: String,
        context: ContextSnapshot?,
        target: DictationTarget?,
        providerID: String,
        model: String?,
        onEvent: @escaping @Sendable (AgentActionEvent) -> Void
    ) async throws -> AgentRuntimeServiceResult {
        try await runIfAvailable(
            taskID: taskID,
            instruction: instruction,
            context: context,
            target: target,
            model: model,
            onEvent: onEvent
        )
    }
}

enum AgentRuntimeServiceResult: Equatable, Sendable {
    case unavailable(AgentRuntimeAvailability)
    case completed(AgentRuntimeResult)
}

struct DefaultAgentRuntimeService: AgentRuntimeServing {
    private let detector: any AgentRuntimeAvailabilityDetecting
    private let workspaceManager: AgentRuntimeWorkspaceManager
    private let client: any AgentRuntimeClient
    private let screenshotProvider: SystemScreenshotProvider
    private let localAgentDetectors: [String: any AgentRuntimeAvailabilityDetecting]
    private let localAgentClients: [String: any AgentRuntimeClient]

    init(
        detector: any AgentRuntimeAvailabilityDetecting,
        workspaceManager: AgentRuntimeWorkspaceManager,
        client: any AgentRuntimeClient,
        screenshotProvider: SystemScreenshotProvider = SystemScreenshotProvider(),
        localAgentDetectors: [String: any AgentRuntimeAvailabilityDetecting]? = nil,
        localAgentClients: [String: any AgentRuntimeClient]? = nil
    ) {
        self.detector = detector
        self.workspaceManager = workspaceManager
        self.client = client
        self.screenshotProvider = screenshotProvider
        let defaultDetectors = Self.defaultLocalAgentDetectors()
        self.localAgentDetectors = localAgentDetectors.map {
            defaultDetectors.merging($0) { _, override in override }
        } ?? defaultDetectors
        let defaultClients = Self.defaultLocalAgentClients()
        self.localAgentClients = localAgentClients.map {
            defaultClients.merging($0) { _, override in override }
        } ?? defaultClients
    }

    func availability(forceRefresh: Bool = false) async -> AgentRuntimeAvailability {
        await detector.cachedOrDetect(forceRefresh: forceRefresh)
    }

    func availability(forceRefresh: Bool = false, providerID: String) async -> AgentRuntimeAvailability {
        if providerID.caseInsensitiveCompare(AgentProviderRegistry.codex.providerID) == .orderedSame {
            return await availability(forceRefresh: forceRefresh)
        }
        guard let detector = localAgentDetectors[providerID] else {
            let now = Date()
            return AgentRuntimeAvailability(
                providerID: providerID,
                status: .unavailable(reason: "未注册的本机 provider"),
                detectedAt: now,
                expiresAt: now,
                cliPath: nil,
                cliVersion: nil
            )
        }
        return await detector.cachedOrDetect(forceRefresh: forceRefresh)
    }

    func runIfAvailable(
        taskID: String,
        instruction: String,
        context: ContextSnapshot?,
        target: DictationTarget?,
        model: String?,
        onEvent: @escaping @Sendable (AgentActionEvent) -> Void
    ) async throws -> AgentRuntimeServiceResult {
        let availability = await detector.cachedOrDetect(forceRefresh: false)
        guard availability.isAvailable, let cliPath = availability.cliPath else {
            return .unavailable(availability)
        }
        workspaceManager.cleanupManagedFiles()
        let workspace = try workspaceManager.prepareSession(taskID: taskID)
        let artifactSnapshot = workspaceManager.artifactSnapshot(workspace: workspace)
        let screenContext = await captureScreenContextIfAvailable(
            workspace: workspace,
            context: context,
            target: target
        )
        let request = AgentRuntimeRequest(
            taskID: taskID,
            instruction: instruction,
            context: context,
            target: target,
            workspace: workspace,
            screenContext: screenContext,
            model: model
        )
        do {
            let result = try await client.run(
                request: request,
                cliPath: cliPath,
                cliVersion: availability.cliVersion,
                onEvent: onEvent
            )
            let artifacts = workspaceManager.artifactsModified(since: artifactSnapshot, workspace: workspace)
            return .completed(result.withArtifacts(artifacts))
        } catch AgentRuntimeClientError.failed(let trace) {
            let artifacts = workspaceManager.artifactsModified(since: artifactSnapshot, workspace: workspace)
            throw AgentRuntimeClientError.failed(trace.withArtifacts(artifacts))
        }
    }

    private func captureScreenContextIfAvailable(
        workspace: AgentRuntimeSessionWorkspace,
        context: ContextSnapshot?,
        target: DictationTarget?
    ) async -> ScreenContextSnapshot? {
        let hasVisualContext = context?.visualContentAvailable == true ||
            context?.sources.contains(.visualFallback) == true
        let shouldCaptureImage = Self.shouldCaptureScreenImage(context: context, target: target)
        guard hasVisualContext || target != nil || context != nil else {
            return nil
        }

        let imagePath: String?
        if shouldCaptureImage,
           let image = await screenshotProvider.captureWindowImage(target: target),
           let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            let imageURL = workspace.screenshotsDirectory
                .appendingPathComponent("\(workspace.taskID)-screen.png", isDirectory: false)
            do {
                try data.write(to: imageURL, options: .atomic)
                imagePath = imageURL.path
            } catch {
                imagePath = nil
            }
        } else {
            imagePath = nil
        }

        guard imagePath != nil || context != nil || target != nil else {
            return nil
        }
        return ScreenContextSnapshot(
            thumbnailPath: imagePath,
            imagePath: imagePath,
            appName: context?.targetAppName ?? target?.appName,
            bundleID: context?.targetAppBundleID ?? target?.bundleID,
            windowTitle: context?.windowTitle ?? target?.windowTitle,
            capturedAt: Date()
            )
    }

    static func shouldCaptureScreenImage(context: ContextSnapshot?, target: DictationTarget?) -> Bool {
        guard let target else { return false }
        if context?.warnings.contains("self_target_context_skipped") == true {
            return false
        }
        return context?.visualContentAvailable == true ||
            context?.sources.contains(.visualFallback) == true ||
            context == nil && target.bundleID != nil
    }

    func runIfAvailable(
        taskID: String,
        instruction: String,
        context: ContextSnapshot?,
        target: DictationTarget?,
        providerID: String,
        model: String?,
        onEvent: @escaping @Sendable (AgentActionEvent) -> Void
    ) async throws -> AgentRuntimeServiceResult {
        if providerID.caseInsensitiveCompare(AgentProviderRegistry.codex.providerID) == .orderedSame {
            return try await runIfAvailable(
                taskID: taskID,
                instruction: instruction,
                context: context,
                target: target,
                model: model,
                onEvent: onEvent
            )
        }
        let availability = await availability(forceRefresh: false, providerID: providerID)
        guard availability.isAvailable, let cliPath = availability.cliPath else {
            return .unavailable(availability)
        }
        guard let client = localAgentClients[providerID] else {
            throw AgentRuntimeError.unavailable("未注册的本机 runtime adapter")
        }
        workspaceManager.cleanupManagedFiles()
        let workspace = try workspaceManager.prepareSession(taskID: taskID)
        let artifactSnapshot = workspaceManager.artifactSnapshot(workspace: workspace)
        let screenContext = await captureScreenContextIfAvailable(
            workspace: workspace,
            context: context,
            target: target
        )
        let request = AgentRuntimeRequest(
            taskID: taskID,
            instruction: instruction,
            context: context,
            target: target,
            workspace: workspace,
            screenContext: screenContext,
            model: model
        )
        do {
            let result = try await client.run(
                request: request,
                cliPath: cliPath,
                cliVersion: availability.cliVersion,
                onEvent: onEvent
            )
            let artifacts = workspaceManager.artifactsModified(since: artifactSnapshot, workspace: workspace)
            return .completed(result.withArtifacts(artifacts))
        } catch AgentRuntimeClientError.failed(let trace) {
            let artifacts = workspaceManager.artifactsModified(since: artifactSnapshot, workspace: workspace)
            throw AgentRuntimeClientError.failed(trace.withArtifacts(artifacts))
        }
    }

    private static func defaultLocalAgentDetectors() -> [String: any AgentRuntimeAvailabilityDetecting] {
        Dictionary(
            uniqueKeysWithValues: AgentProviderRegistry.enabledRuntimeProviders
                .filter { $0.providerID != AgentProviderRegistry.codex.providerID }
                .map { descriptor in
                    (
                        descriptor.providerID,
                        LocalAgentCLIAdapter(
                            descriptor: descriptor,
                            configuration: .default(for: descriptor)
                        ) as any AgentRuntimeAvailabilityDetecting
                    )
                }
        )
    }

    private static func defaultLocalAgentClients() -> [String: any AgentRuntimeClient] {
        Dictionary(
            uniqueKeysWithValues: AgentProviderRegistry.enabledRuntimeProviders
                .filter { $0.providerID != AgentProviderRegistry.codex.providerID }
                .map { descriptor in
                    (
                        descriptor.providerID,
                        LocalAgentCLIRuntimeClient(descriptor: descriptor) as any AgentRuntimeClient
                    )
                }
        )
    }
}

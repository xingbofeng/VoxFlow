import AppKit
import Foundation

protocol AgentRuntimeServing: Sendable {
    func availability(forceRefresh: Bool) async -> AgentRuntimeAvailability
    func runIfAvailable(
        taskID: String,
        instruction: String,
        context: ContextSnapshot?,
        target: DictationTarget?,
        model: String?,
        onEvent: @escaping @Sendable (AgentActionEvent) -> Void
    ) async throws -> AgentRuntimeServiceResult
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

    init(
        detector: any AgentRuntimeAvailabilityDetecting,
        workspaceManager: AgentRuntimeWorkspaceManager,
        client: any AgentRuntimeClient,
        screenshotProvider: SystemScreenshotProvider = SystemScreenshotProvider()
    ) {
        self.detector = detector
        self.workspaceManager = workspaceManager
        self.client = client
        self.screenshotProvider = screenshotProvider
    }

    func availability(forceRefresh: Bool = false) async -> AgentRuntimeAvailability {
        await detector.cachedOrDetect(forceRefresh: forceRefresh)
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
        let workspace = try workspaceManager.prepareSession(taskID: taskID)
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
        let result = try await client.run(
            request: request,
            cliPath: cliPath,
            cliVersion: availability.cliVersion,
            onEvent: onEvent
        )
        workspaceManager.cleanupSessionTemporaryFiles(workspace)
        return .completed(result)
    }

    private func captureScreenContextIfAvailable(
        workspace: AgentRuntimeSessionWorkspace,
        context: ContextSnapshot?,
        target: DictationTarget?
    ) async -> ScreenContextSnapshot? {
        let hasVisualContext = context?.visualContentAvailable == true ||
            context?.sources.contains(.visualFallback) == true
        guard hasVisualContext || target != nil else {
            return nil
        }

        let imagePath: String?
        if let image = await screenshotProvider.captureWindowImage(target: target),
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
}

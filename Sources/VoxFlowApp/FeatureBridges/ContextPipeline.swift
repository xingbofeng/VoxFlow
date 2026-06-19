import AppKit
import Foundation
import ScreenCaptureKit
import Vision

// MARK: - ContextCollecting

protocol ContextCollecting: Sendable {
    func collect(
        target: DictationTarget?,
        visionSupported: Bool
    ) async -> ContextSnapshot
}

// MARK: - ContextPipeline

struct ContextPipeline: ContextCollecting {
    static let maxTotalCharacters = 4000
    static let timeoutMilliseconds = 500
    static let minimumAccessibilityCharacters = 50

    private let windowInfoProvider: any WindowInfoProviding
    private let accessibilityProvider: any AccessibilityProviding
    private let screenshotProvider: any ScreenshotProviding

    init(
        windowInfoProvider: any WindowInfoProviding = SystemWindowInfoProvider(),
        accessibilityProvider: any AccessibilityProviding = SystemAccessibilityProvider(),
        screenshotProvider: any ScreenshotProviding = SystemScreenshotProvider()
    ) {
        self.windowInfoProvider = windowInfoProvider
        self.accessibilityProvider = accessibilityProvider
        self.screenshotProvider = screenshotProvider
    }

    func collect(
        target: DictationTarget?,
        visionSupported: Bool
    ) async -> ContextSnapshot {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(Self.timeoutMilliseconds))

        var windowTitle: String?
        var bundleID = target?.bundleID
        var appName = target?.appName
        var sources: [ContextSource] = []
        var warnings: [String] = []
        var visibleText: String?
        var selectedText: String?
        var inputAreaText: String?
        var visualContentAvailable = false

        // 1. Window metadata
        if let target {
            windowTitle = target.windowTitle ?? windowInfoProvider.windowTitle(pid: target.pid)
            if bundleID == nil { bundleID = target.bundleID }
            if appName == nil { appName = target.appName }
            if windowTitle != nil || bundleID != nil || appName != nil {
                sources.append(.windowMetadata)
            }
        }

        // 2. Security gate: check if the focused element is a secure text field
        let isSecure = accessibilityProvider.isSecureTextField(pid: target?.pid)
        if isSecure {
            warnings.append("secure_text_field_detected")
            // Block all accessibility collection for secure fields
            let snapshot = ContextSnapshot(
                windowTitle: windowTitle,
                targetAppBundleID: bundleID,
                targetAppName: appName,
                visibleText: nil,
                selectedText: nil,
                inputAreaText: nil,
                visualContentAvailable: false,
                sources: sources,
                trimmedLength: 0,
                warnings: warnings
            )
            return snapshot
        }

        // 3. Accessibility visible text
        if ContinuousClock.now < deadline {
            let visible = accessibilityProvider.visibleText(pid: target?.pid)
            if let visible = visible.flatMap(ContextTextSanitizer.sanitize),
               !Self.isNoise(visible) {
                visibleText = visible
                sources.append(.accessibilityVisibleText)
            }
        } else {
            warnings.append("context_collection_timeout")
        }

        // 4. Selected text
        if ContinuousClock.now < deadline {
            let selected = accessibilityProvider.selectedText(pid: target?.pid)
            if let selected = selected.flatMap(ContextTextSanitizer.sanitize),
               !Self.isNoise(selected) {
                selectedText = selected
                sources.append(.accessibilitySelectedText)
            }
        } else if !warnings.contains("context_collection_timeout") {
            warnings.append("context_collection_timeout")
        }

        // 5. Input area text
        if ContinuousClock.now < deadline {
            let inputArea = accessibilityProvider.inputAreaText(pid: target?.pid)
            if let inputArea = inputArea.flatMap(ContextTextSanitizer.sanitize),
               !Self.isNoise(inputArea) {
                inputAreaText = inputArea
                sources.append(.accessibilityInputArea)
            }
        } else if !warnings.contains("context_collection_timeout") {
            warnings.append("context_collection_timeout")
        }

        // 6. Deduplicate
        let deduped = Self.deduplicate(
            visibleText: visibleText,
            selectedText: selectedText,
            inputAreaText: inputAreaText
        )
        visibleText = deduped.visibleText
        selectedText = deduped.selectedText
        inputAreaText = deduped.inputAreaText

        // 7. Trim to max length with source-aware trimming
        let trimmed = Self.trimToLimit(
            visibleText: visibleText,
            selectedText: selectedText,
            inputAreaText: inputAreaText,
            maxLength: Self.maxTotalCharacters
        )
        visibleText = trimmed.visibleText
        selectedText = trimmed.selectedText
        inputAreaText = trimmed.inputAreaText

        var trimmedLength = (visibleText?.count ?? 0)
            + (selectedText?.count ?? 0)
            + (inputAreaText?.count ?? 0)

        // 8. Visual fallback: only when accessibility text is insufficient
        let accessibilityTotal = trimmedLength
        if accessibilityTotal < Self.minimumAccessibilityCharacters {
            if visionSupported {
                if ContinuousClock.now < deadline {
                    visualContentAvailable = screenshotProvider.canCaptureScreen()
                    if visualContentAvailable {
                        sources.append(.visualFallback)
                        if let visualText = await screenshotProvider.visibleText(target: target)
                            .flatMap(ContextTextSanitizer.sanitize),
                           !Self.isNoise(visualText) {
                            visibleText = visualText
                            let visualTrimmed = Self.trimToLimit(
                                visibleText: visibleText,
                                selectedText: selectedText,
                                inputAreaText: inputAreaText,
                                maxLength: Self.maxTotalCharacters
                            )
                            visibleText = visualTrimmed.visibleText
                            selectedText = visualTrimmed.selectedText
                            inputAreaText = visualTrimmed.inputAreaText
                            trimmedLength = (visibleText?.count ?? 0)
                                + (selectedText?.count ?? 0)
                                + (inputAreaText?.count ?? 0)
                        }
                    } else {
                        warnings.append("screen_recording_not_authorized")
                    }
                    // Screenshot is transient; only OCR text is retained in the context snapshot.
                } else {
                    warnings.append("visual_fallback_timeout")
                }
            } else {
                warnings.append("vision_not_supported")
            }
        }

        return ContextSnapshot(
            windowTitle: windowTitle,
            targetAppBundleID: bundleID,
            targetAppName: appName,
            visibleText: visibleText,
            selectedText: selectedText,
            inputAreaText: inputAreaText,
            visualContentAvailable: visualContentAvailable,
            sources: sources,
            trimmedLength: trimmedLength,
            warnings: warnings
        )
    }

    // MARK: - Text processing

    /// Deduplicate identical text from different sources.
    static func deduplicate(
        visibleText: String?,
        selectedText: String?,
        inputAreaText: String?
    ) -> (visibleText: String?, selectedText: String?, inputAreaText: String?) {
        var result = (visibleText: visibleText, selectedText: selectedText, inputAreaText: inputAreaText)

        // If selected text is a subset of visible text, remove it from selected
        if let visible = visibleText, let selected = selectedText,
           visible.contains(selected) {
            result.selectedText = nil
        }

        // If input area text matches visible text, remove it
        if let visible = result.visibleText, let inputArea = result.inputAreaText,
           visible == inputArea {
            result.inputAreaText = nil
        }

        // If input area text matches selected text, remove it
        if let selected = result.selectedText, let inputArea = result.inputAreaText,
           selected == inputArea {
            result.inputAreaText = nil
        }

        return result
    }

    /// Trim text fields proportionally to fit within maxLength.
    static func trimToLimit(
        visibleText: String?,
        selectedText: String?,
        inputAreaText: String?,
        maxLength: Int
    ) -> (visibleText: String?, selectedText: String?, inputAreaText: String?) {
        let totalLength = (visibleText?.count ?? 0)
            + (selectedText?.count ?? 0)
            + (inputAreaText?.count ?? 0)

        guard totalLength > maxLength else {
            return (visibleText, selectedText, inputAreaText)
        }

        // Priority: selectedText > inputAreaText > visibleText
        // Trim visibleText first (it's typically the largest)
        var vText = visibleText
        let sText = selectedText
        var iText = inputAreaText

        // First pass: trim visible text
        let otherLength = (sText?.count ?? 0) + (iText?.count ?? 0)
        let availableForVisible = max(0, maxLength - otherLength)
        if let v = vText, v.count > availableForVisible {
            vText = String(v.prefix(availableForVisible))
        }

        // Second pass: if still over, trim input area
        let currentTotal = (vText?.count ?? 0) + (sText?.count ?? 0) + (iText?.count ?? 0)
        if currentTotal > maxLength {
            let availableForInput = max(0, maxLength - (vText?.count ?? 0) - (sText?.count ?? 0))
            if let i = iText, i.count > availableForInput {
                iText = String(i.prefix(availableForInput))
            }
        }

        return (vText, sText, iText)
    }

    /// Check if text is noise (whitespace-only or very short).
    static func isNoise(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count < 2
    }
}

enum ContextTextSanitizer {
    private static let chromeLabels: Set<String> = [
        "关闭按钮",
        "最小化按钮",
        "缩放按钮",
        "全屏按钮",
        "工具栏",
        "侧边栏",
        "Close button",
        "Minimize button",
        "Zoom button",
        "Full Screen button",
    ]

    private static let mojibakeMarkers = [
        "\u{FFFD}",
        "锟斤拷",
        "烫烫烫",
        "���",
    ]

    static func sanitize(_ text: String) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !isInvalidLine($0) }

        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    private static func isInvalidLine(_ line: String) -> Bool {
        guard line.count >= 2 else { return true }
        if chromeLabels.contains(line) { return true }
        if mojibakeMarkers.contains(where: line.contains) { return true }
        if line.hasPrefix("AX"), line.contains("Button") { return true }
        return isStandaloneJSON(line)
    }

    private static func isStandaloneJSON(_ line: String) -> Bool {
        guard let first = line.first,
              (first == "{" || first == "["),
              let data = line.data(using: .utf8) else {
            return false
        }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}

// MARK: - WindowInfoProviding

protocol WindowInfoProviding: Sendable {
    func windowTitle(pid: Int?) -> String?
}

struct SystemWindowInfoProvider: WindowInfoProviding {
    func windowTitle(pid: Int?) -> String? {
        guard let pid else { return nil }
        // Try to get the window title from the focused window
        // Use CGWindowListCopyWindowInfo for the frontmost window.
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }
        for window in windowList {
            if let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
               ownerPID == pid,
               let title = window[kCGWindowName as String] as? String,
               !title.isEmpty {
                return title
            }
        }
        return nil
    }
}

// MARK: - AccessibilityProviding

protocol AccessibilityProviding: Sendable {
    func visibleText(pid: Int?) -> String?
    func selectedText(pid: Int?) -> String?
    func inputAreaText(pid: Int?) -> String?
    func isSecureTextField(pid: Int?) -> Bool
}

enum AccessibilityVisibleTextSummary {
    static func make(
        from candidates: [String],
        maxCharacters: Int = ContextPipeline.maxTotalCharacters
    ) -> String? {
        var seen = Set<String>()
        var lines: [String] = []
        var remaining = maxCharacters

        for candidate in candidates {
            let normalizedLines = (ContextTextSanitizer.sanitize(candidate) ?? "")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !ContextPipeline.isNoise($0) }

            for line in normalizedLines {
                guard !seen.contains(line), remaining > 0 else { continue }
                seen.insert(line)

                if line.count > remaining {
                    lines.append(String(line.prefix(remaining)))
                    remaining = 0
                } else {
                    lines.append(line)
                    remaining -= line.count
                }
            }
        }

        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }
}

struct SystemAccessibilityProvider: AccessibilityProviding {
    func visibleText(pid: Int?) -> String? {
        guard let pid else { return nil }

        var candidates: [String] = []
        if let element = focusedElement(pid: pid) {
            appendTextAttributes(from: element, to: &candidates)
        }

        var visited = Set<UInt>()
        var visitedCount = 0
        for element in windowElements(pid: pid) {
            collectText(
                from: element,
                depth: 0,
                visited: &visited,
                visitedCount: &visitedCount,
                candidates: &candidates
            )
        }

        return AccessibilityVisibleTextSummary.make(from: candidates)
    }

    func selectedText(pid: Int?) -> String? {
        guard let pid, let element = focusedElement(pid: pid) else { return nil }
        return axAttribute(element, kAXSelectedTextAttribute) as? String
    }

    func inputAreaText(pid: Int?) -> String? {
        guard let pid, let element = focusedElement(pid: pid) else { return nil }
        // Check if the element is a text field or text area
        let role = axAttribute(element, kAXRoleAttribute) as? String
        guard role == kAXTextFieldRole || role == kAXTextAreaRole else {
            return nil
        }
        return axAttribute(element, kAXValueAttribute) as? String
    }

    func isSecureTextField(pid: Int?) -> Bool {
        guard let pid, let element = focusedElement(pid: pid) else { return false }
        // Check if the focused element is a secure text field
        if let isSecure = axAttribute(element, "AXIsSecureTextField") as? Bool {
            return isSecure
        }
        // Also check the subrole for password fields
        if let subrole = axAttribute(element, kAXSubroleAttribute) as? String,
           subrole == "AXSecureTextField" {
            return true
        }
        return false
    }

    private func focusedElement(pid: Int) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid_t(pid))
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            app,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard result == .success else { return nil }
        return (focused as! AXUIElement)
    }

    private func windowElements(pid: Int) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid_t(pid))
        if let focusedWindow = axAttribute(app, kAXFocusedWindowAttribute) {
            return [focusedWindow as! AXUIElement]
        }
        if let windows = axAttribute(app, kAXWindowsAttribute) as? [AnyObject] {
            let elements = windows.map { $0 as! AXUIElement }
            if !elements.isEmpty {
                return elements
            }
        }
        return [app]
    }

    private func collectText(
        from element: AXUIElement,
        depth: Int,
        visited: inout Set<UInt>,
        visitedCount: inout Int,
        candidates: inout [String]
    ) {
        guard depth <= 10, visitedCount < 500 else { return }

        let elementID = UInt(bitPattern: Unmanaged.passUnretained(element).toOpaque())
        guard !visited.contains(elementID) else { return }
        visited.insert(elementID)
        visitedCount += 1

        guard !isSecure(element) else { return }
        appendTextAttributes(from: element, to: &candidates)

        for attribute in [
            kAXChildrenAttribute,
            "AXVisibleChildren",
            "AXRows",
            "AXColumns",
            "AXCells",
            "AXContents"
        ] {
            guard let children = axAttribute(element, attribute) as? [AXUIElement] else {
                continue
            }
            for child in children {
                collectText(
                    from: child,
                    depth: depth + 1,
                    visited: &visited,
                    visitedCount: &visitedCount,
                    candidates: &candidates
                )
            }
        }
    }

    private func appendTextAttributes(from element: AXUIElement, to candidates: inout [String]) {
        for attribute in [
            kAXTitleAttribute,
            kAXValueAttribute,
            kAXDescriptionAttribute,
            kAXHelpAttribute,
            kAXPlaceholderValueAttribute
        ] {
            if let value = axAttribute(element, attribute) as? String {
                candidates.append(value)
            }
        }
    }

    private func isSecure(_ element: AXUIElement) -> Bool {
        if let isSecure = axAttribute(element, "AXIsSecureTextField") as? Bool {
            return isSecure
        }
        if let subrole = axAttribute(element, kAXSubroleAttribute) as? String,
           subrole == "AXSecureTextField" {
            return true
        }
        return false
    }

    private func axAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }
}

// MARK: - ScreenshotProviding

protocol ScreenshotProviding: Sendable {
    func canCaptureScreen() -> Bool
    func visibleText(target: DictationTarget?) async -> String?
}

struct ScreenshotWindowCandidate: Equatable, Sendable {
    let windowID: CGWindowID
    let pid: Int
    let layer: Int
    let isOnScreen: Bool
    let isActive: Bool
    let frame: CGRect
}

struct SystemScreenshotProvider: ScreenshotProviding {
    func canCaptureScreen() -> Bool {
        // Check screen recording permission without prompting. Permission requests
        // belong in onboarding/settings, not in the hotkey-to-HUD workflow.
        CGPreflightScreenCaptureAccess()
    }

    func visibleText(target: DictationTarget?) async -> String? {
        guard canCaptureScreen(),
              let image = await captureWindowImage(target: target) else {
            return nil
        }

        let request = Self.makeRecognitionRequest()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let candidates = request.results?.compactMap {
            $0.topCandidates(1).first?.string
        } ?? []
        return AccessibilityVisibleTextSummary.make(from: candidates)
    }

    static func makeRecognitionRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        return request
    }

    static func selectWindow(
        from candidates: [ScreenshotWindowCandidate],
        target: DictationTarget?
    ) -> ScreenshotWindowCandidate? {
        guard let pid = target?.pid else { return nil }
        let eligible = candidates.filter {
            $0.pid == pid
                && $0.layer == 0
                && $0.isOnScreen
                && $0.frame.width >= 80
                && $0.frame.height >= 80
        }

        if let rawWindowID = target?.windowID,
           let windowID = CGWindowID(rawWindowID),
           let exact = eligible.first(where: { $0.windowID == windowID }) {
            return exact
        }
        if let active = eligible.first(where: \.isActive) {
            return active
        }
        return eligible.max { $0.frame.area < $1.frame.area }
    }

    private func captureWindowImage(target: DictationTarget?) async -> CGImage? {
        guard let target else {
            return nil
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: true
            )
        } catch {
            return nil
        }

        let candidates = content.windows.compactMap { window -> ScreenshotWindowCandidate? in
            guard let pid = window.owningApplication?.processID else { return nil }
            return ScreenshotWindowCandidate(
                windowID: window.windowID,
                pid: Int(pid),
                layer: window.windowLayer,
                isOnScreen: window.isOnScreen,
                isActive: window.isActive,
                frame: window.frame
            )
        }
        guard let selected = Self.selectWindow(from: candidates, target: target),
              let window = content.windows.first(where: {
                  $0.windowID == selected.windowID
              }) else {
            return nil
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let longestSide = max(window.frame.width, window.frame.height)
        let captureScale = max(1, min(2, 2400 / max(1, longestSide)))
        configuration.width = max(1, Int(window.frame.width * captureScale))
        configuration.height = max(1, Int(window.frame.height * captureScale))
        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            return nil
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(0, width) * max(0, height)
    }
}

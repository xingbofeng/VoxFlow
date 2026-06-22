import ApplicationServices
import AppKit
import Foundation
import VoxFlowVoiceCorrection

@MainActor
final class AccessibilityFocusedTextObserver: FocusedTextObserving {
    private let logger = AppLogger.dictation

    private let maximumCachedElements = 32
    private var elementsByIdentity: [String: AXUIElement] = [:]
    private var elementIdentityOrder: [String] = []

    func capture() -> FocusedTextObservation? {
        guard AXIsProcessTrusted() else {
            logger.warning("AccessibilityFocusedTextObserver capture skipped: not trusted")
            return nil
        }
        guard let element = focusedTextElement() else {
            logger.debug("AccessibilityFocusedTextObserver capture failed: no focused text element")
            return nil
        }
        return observation(for: element)
    }

    func recapture(
        matching baseline: FocusedTextObservation
    ) -> FocusedTextObservation? {
        guard AXIsProcessTrusted() else {
            logger.debug("AccessibilityFocusedTextObserver recapture skipped: not trusted")
            return nil
        }
        guard let element = elementsByIdentity[baseline.elementIdentity] else {
            logger.debug("AccessibilityFocusedTextObserver recapture miss: identity=\(baseline.elementIdentity)")
            return nil
        }
        return observation(for: element)
    }

    func focusedInputIsSecure() -> Bool {
        guard AXIsProcessTrusted(),
              let element = focusedTextElement()
        else {
            logger.debug("AccessibilityFocusedTextObserver focusedInputIsSecure fallback false")
            return false
        }
        return isSecureField(element)
    }

    private func focusedTextElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success else {
            logger.debug("AccessibilityFocusedTextObserver focusedTextElement failed: no focused element attribute")
            return nil
        }

        let element = focusedElement as! AXUIElement
        guard isTextElement(element) else {
            logger.debug("AccessibilityFocusedTextObserver focusedTextElement not text element")
            return nil
        }
        return element
    }

    private func observation(for element: AXUIElement) -> FocusedTextObservation? {
        let identity = String(CFHash(element))
        elementsByIdentity[identity] = element
        rememberElementIdentity(identity)
        let secure = isSecureField(element)
        let bundleIdentifier = bundleIdentifier(for: element)

        if secure {
            logger.debug("AccessibilityFocusedTextObserver observation secure field identity=\(identity)")
            return FocusedTextObservation(
                elementIdentity: identity,
                value: "",
                selectedRange: nil,
                bundleIdentifier: bundleIdentifier,
                isSecureField: true
            )
        }

        guard let value = stringAttribute(kAXValueAttribute, from: element) else {
            logger.warning("AccessibilityFocusedTextObserver observation missing value identity=\(identity)")
            return nil
        }

        logger.debug("AccessibilityFocusedTextObserver observation captured identity=\(identity) length=\(value.count)")
        return FocusedTextObservation(
            elementIdentity: identity,
            value: value,
            selectedRange: selectedRange(for: element),
            bundleIdentifier: bundleIdentifier,
            isSecureField: false
        )
    }

    private func rememberElementIdentity(_ identity: String) {
        elementIdentityOrder.removeAll { $0 == identity }
        elementIdentityOrder.append(identity)
        pruneElementCacheIfNeeded()
    }

    private func pruneElementCacheIfNeeded() {
        while elementIdentityOrder.count > maximumCachedElements {
            let expired = elementIdentityOrder.removeFirst()
            elementsByIdentity.removeValue(forKey: expired)
        }
    }

    private func isTextElement(_ element: AXUIElement) -> Bool {
        guard let role = stringAttribute(kAXRoleAttribute, from: element) else {
            return false
        }
        let textRoles: Set<String> = [
            "AXTextField",
            "AXTextArea",
            "AXComboBox",
            "AXSearchField",
            "AXWebArea",
        ]
        return textRoles.contains(role) || isSecureField(element)
    }

    private func isSecureField(_ element: AXUIElement) -> Bool {
        if stringAttribute(kAXRoleAttribute, from: element) == "AXSecureTextField" {
            return true
        }
        return stringAttribute(kAXSubroleAttribute, from: element) == "AXSecureTextField"
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func selectedRange(for element: AXUIElement) -> CorrectionTextRange? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return CorrectionTextRange(location: range.location, length: range.length)
    }

    private func bundleIdentifier(for element: AXUIElement) -> String? {
        var pid = pid_t()
        guard AXUIElementGetPid(element, &pid) == .success else {
            return nil
        }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}

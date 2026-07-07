import Shared
import SwiftUI
import UIKit

struct UITestKeyboardHostView: View {
    var body: some View {
        KeyboardHostTextView()
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onAppear {
                resetSharedDictationStateForUITests()
                scheduleSimulatedTranscriptionIfRequested()
            }
    }

    private func resetSharedDictationStateForUITests() {
        let store = SharedStatusStore()
        store.clearConsumedTranscription()
        store.writeStatus(.idle)

        for key in [
            SharedKeys.pendingClipboardLaunched,
            SharedKeys.pendingClipboardText,
            SharedKeys.pendingClipboardTimestamp
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }

        if ProcessInfo.processInfo.arguments.contains("--mashangxie-ui-test-auto-transcription") {
            BridgeModeStore.write(.appGroup)
        }
    }

    private func scheduleSimulatedTranscriptionIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--mashangxie-ui-test-auto-transcription") else {
            return
        }

        let store = SharedStatusStore()
        let deadline = Date().addingTimeInterval(60)

        func waitForRecordingThenPost() {
            let status = store.readStatus()
            if status == .requested || status == .recording || status == .transcribing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    store.writeTranscription("语音")
                    store.writeStatus(.ready)
                    DarwinNotificationCenter.post(DarwinNotificationName.transcriptionReady)
                }
                return
            }

            guard Date() < deadline else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                waitForRecordingThenPost()
            }
        }

        waitForRecordingThenPost()
    }
}

private struct KeyboardHostTextView: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.accessibilityIdentifier = "keyboardHostTextView"
        textView.font = .preferredFont(forTextStyle: .title2)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.keyboardType = .default
        textView.returnKeyType = .default
        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 28, left: 20, bottom: 28, right: 20)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            textView.becomeFirstResponder()
        }

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {}
}

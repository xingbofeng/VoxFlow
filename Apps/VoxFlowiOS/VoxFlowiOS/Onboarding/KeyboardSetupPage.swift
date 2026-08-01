// DictusApp/Onboarding/KeyboardSetupPage.swift adapted for Mashangxie.
import Shared
import SwiftUI
import UIKit

struct KeyboardSetupPage: View {
    let onNext: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboardDetected = false
    @State private var isCheckingKeyboard = false
    @State private var keyboardCheckTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            Image(systemName: "keyboard")
                .font(.system(size: 64))
                .foregroundColor(Color.dictusAccent)
                .padding(.bottom, 24)

            Text(L10n.t("onboarding.keyboard.title"))
                .font(.dictusHeading)
                .foregroundStyle(.primary)
                .padding(.bottom, 16)

            settingsCard
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

            Button(action: openSettings) {
                Label(L10n.t("onboarding.keyboard.open_settings"), systemImage: "arrow.up.right")
                    .font(.dictusBody)
                    .foregroundColor(Color.dictusAccent)
            }
            .padding(.bottom, 20)

            Text(L10n.t("onboarding.keyboard.auto_detect"))
                .font(.dictusCaption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            Text(L10n.t("onboarding.keyboard.restart_note"))
                .font(.dictusCaption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)

            if keyboardDetected {
                Label(L10n.t("onboarding.keyboard.detected"), systemImage: "checkmark.circle.fill")
                    .font(.dictusBody)
                    .foregroundColor(.dictusSuccess)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }

            Spacer()

            OnboardingPrimaryButton(title: L10n.t("onboarding.continue"), action: onNext)
                .padding(.bottom, 16)
                .opacity(keyboardDetected ? 1 : 0.35)
        }
        .onAppear {
            checkKeyboardInstalled()
        }
        .onDisappear {
            keyboardCheckTask?.cancel()
            keyboardCheckTask = nil
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, !isCheckingKeyboard else { return }
            isCheckingKeyboard = true
            keyboardCheckTask?.cancel()
            keyboardCheckTask = Task {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    checkKeyboardInstalled()
                    isCheckingKeyboard = false
                }
            }
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.t("onboarding.keyboard.step_add"), systemImage: "1.circle.fill")
            Label(L10n.t("onboarding.keyboard.step_full_access"), systemImage: "2.circle.fill")
            Label(L10n.t("onboarding.keyboard.step_return"), systemImage: "3.circle.fill")
        }
        .font(.dictusBody)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .dictusGlass()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func checkKeyboardInstalled() {
        for mode in UITextInputMode.activeInputModes {
            guard let identifier = mode.value(forKey: "identifier") as? String else { continue }
            if identifier.contains("com.mashangxie.ios.keyboard") {
                keyboardDetected = true
                return
            }
        }
    }
}


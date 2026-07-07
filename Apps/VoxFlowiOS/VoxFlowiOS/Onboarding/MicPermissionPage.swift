// DictusApp/Onboarding/MicPermissionPage.swift adapted for Mashangxie.
import AVFoundation
import Shared
import SwiftUI

struct MicPermissionPage: View {
    let onNext: () -> Void

    @State private var permissionGranted: Bool?
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "mic.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(Color.dictusAccent)
                .padding(.bottom, 24)

            Text(L10n.t("onboarding.mic.title"))
                .font(.dictusHeading)
                .foregroundStyle(.primary)
                .padding(.bottom, 16)

            Text(L10n.t("onboarding.mic.subtitle"))
                .font(.dictusBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            if let granted = permissionGranted {
                if granted {
                    Label(L10n.t("onboarding.mic.authorized"), systemImage: "checkmark.circle.fill")
                        .font(.dictusBody)
                        .foregroundColor(.dictusSuccess)
                        .padding(.bottom, 16)
                } else {
                    Text(L10n.t("onboarding.mic.later"))
                        .font(.dictusCaption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 16)
                }
            }

            OnboardingPrimaryButton(
                title: L10n.t("onboarding.continue"),
                action: permissionGranted == nil ? requestPermission : onNext
            )
            .disabled(isRequesting)
            .padding(.bottom, 48)
        }
    }

    private func requestPermission() {
        isRequesting = true

        Self.requestAudioAccess { allowed in
            Task { @MainActor in
                permissionGranted = allowed
                isRequesting = false
                if allowed {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        onNext()
                    }
                }
            }
        }
    }

    private nonisolated static func requestAudioAccess(_ completion: @escaping @Sendable (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }
}

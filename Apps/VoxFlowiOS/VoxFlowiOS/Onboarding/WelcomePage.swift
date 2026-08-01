// DictusApp/Onboarding/WelcomePage.swift adapted for Mashangxie.
import Shared
import SwiftUI

struct WelcomePage: View {
    let onNext: () -> Void

    @State private var showContent = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            BrandWaveform(maxHeight: 100, isProcessing: true)
                .opacity(0.5)
                .padding(.bottom, 24)

            Text(L10n.t("onboarding.welcome.brand"))
                .font(.system(size: 42, weight: .ultraLight, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.bottom, 12)

            Text(L10n.t("onboarding.welcome.tagline"))
                .font(.dictusBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            OnboardingPrimaryButton(title: L10n.t("onboarding.get_started"), action: onNext)
                .padding(.bottom, 48)
                .opacity(showContent ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.6).delay(0.5)) {
                showContent = true
            }
        }
    }
}


// DictusApp/Onboarding/ModeSelectionPage.swift adapted for Mashangxie.
import Shared
import SwiftUI

struct ModeSelectionPage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text(L10n.t("onboarding.mode.title"))
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text(L10n.t("onboarding.mode.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            DefaultLayerPicker()
                .padding(.horizontal, 16)

            providerSummary
                .padding(.horizontal, 32)

            Spacer()

            OnboardingPrimaryButton(title: L10n.t("onboarding.continue"), action: onNext)
                .padding(.bottom, 16)
        }
    }

    private var providerSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("onboarding.provider.title"))
                .font(.dictusCaption)
                .foregroundStyle(.secondary)
            Text(L10n.t("onboarding.provider.subtitle"))
                .font(.dictusBody)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .dictusGlass()
    }
}


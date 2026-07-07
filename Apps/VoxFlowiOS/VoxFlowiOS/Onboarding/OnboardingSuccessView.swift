// DictusApp/Onboarding/OnboardingSuccessView.swift adapted for Mashangxie.
import Shared
import SwiftUI

struct OnboardingSuccessView: View {
    let onComplete: () -> Void

    @State private var checkmarkScale: CGFloat = 0
    @State private var showText = false

    var body: some View {
        ZStack {
            Color.dictusBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.dictusSuccess)
                        .frame(width: 120, height: 120)
                    Image(systemName: "checkmark")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(checkmarkScale)
                .padding(.bottom, 32)

                VStack(spacing: 12) {
                    Text(L10n.t("onboarding.success.title"))
                        .font(.dictusHeading)
                        .foregroundStyle(.primary)
                    Text(L10n.t("onboarding.success.subtitle"))
                        .font(.dictusBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .opacity(showText ? 1 : 0)

                Spacer()

                OnboardingPrimaryButton(title: L10n.t("onboarding.get_started"), action: onComplete)
                    .padding(.bottom, 48)
                    .opacity(showText ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                checkmarkScale = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showText = true
                }
            }
        }
    }
}


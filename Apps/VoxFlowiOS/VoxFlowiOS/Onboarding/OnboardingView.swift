// DictusApp/Onboarding/OnboardingView.swift adapted for Mashangxie.
// Programmatic-only onboarding flow with keyboard, mic, provider, and success steps.
import Shared
import SwiftUI

struct OnboardingView: View {
    @Binding var isComplete: Bool

    @AppStorage(SharedKeys.onboardingCurrentPage, store: AppGroup.preferences)
    private var currentPage: Int = 0

    @State private var completedSteps: Set<Int> = []

    private let totalSteps = 5

    var body: some View {
        ZStack {
            Color.dictusBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch currentPage {
                    case 0:
                        WelcomePage(onNext: { advanceToPage(1) })
                    case 1:
                        MicPermissionPage(onNext: { advanceToPage(2) })
                    case 2:
                        KeyboardSetupPage(onNext: { advanceToPage(3) })
                    case 3:
                        ModeSelectionPage(onNext: { advanceToPage(4) })
                    case 4:
                        OnboardingSuccessView {
                            currentPage = 0
                            isComplete = true
                        }
                    default:
                        WelcomePage(onNext: { advanceToPage(1) })
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
                .id(currentPage)

                stepIndicator
                    .padding(.bottom, 24)
            }
        }
        .interactiveDismissDisabled()
        .animation(.easeInOut(duration: 0.3), value: currentPage)
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Circle()
                    .fill(dotColor(for: step))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.top, 16)
    }

    private func dotColor(for step: Int) -> Color {
        if step == currentPage {
            return .dictusAccent
        } else if completedSteps.contains(step) {
            return .dictusAccent.opacity(0.5)
        } else {
            return .gray.opacity(0.3)
        }
    }

    private func advanceToPage(_ page: Int) {
        completedSteps.insert(currentPage)
        withAnimation {
            currentPage = page
        }
    }
}

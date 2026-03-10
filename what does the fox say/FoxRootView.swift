import SwiftUI

struct FoxRootView: View {
    @StateObject private var viewModel = FoxAppViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true
    @State private var splashDismissTask: Task<Void, Never>?
    @State private var pendingReviewRequestToken: Int?
    @State private var showRatePrompt = false

    var body: some View {
        ZStack {
            FoxHomeView()
                .environmentObject(viewModel)
                .opacity(viewModel.showOnboarding ? 0 : 1)

            if viewModel.showOnboarding {
                FoxOnboardingView()
                    .environmentObject(viewModel)
                    .transition(.opacity)
            }

            if showSplash {
                FoxSplashView {
                    dismissSplash(reason: "tap")
                }
                .transition(.opacity)
                .zIndex(10)
            }

            if showRatePrompt {
                FoxRatePromptView(
                    onRateNow: {
                        debugLog(.ui, "rate prompt action=rate_now")
                        dismissRatePrompt()
                    },
                    onNotNow: {
                        debugLog(.ui, "rate prompt action=not_now")
                        dismissRatePrompt()
                    }
                )
                .transition(.opacity.combined(with: .scale))
                .zIndex(20)
            }
        }
        .background(FoxTheme.pageGradient.ignoresSafeArea())
        .onAppear {
            debugLog(.lifecycle, "root onAppear")
            viewModel.onAppear()
            showSplashOverlayIfNeeded()
            notifyMainPageVisibleIfNeeded()
        }
        .onDisappear {
            splashDismissTask?.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            debugLog(.lifecycle, "scenePhase=\(String(describing: phase))")
            viewModel.setAppActive(phase == .active)
            if phase == .active, showSplash {
                showSplashOverlayIfNeeded()
            }
            notifyMainPageVisibleIfNeeded()
        }
        .onChange(of: showSplash) { _, _ in
            notifyMainPageVisibleIfNeeded()
            presentPendingRatePromptIfPossible()
        }
        .onChange(of: viewModel.showOnboarding) { _, _ in
            notifyMainPageVisibleIfNeeded()
            presentPendingRatePromptIfPossible()
        }
        .onChange(of: viewModel.reviewRequestToken) { _, token in
            guard token > 0 else { return }
            pendingReviewRequestToken = token
            debugLog(.ui, "review prompt armed token=\(token)")
            presentPendingRatePromptIfPossible()
        }
    }

    private func showSplashOverlayIfNeeded() {
        guard showSplash else { return }
        debugLog(.ui, "splash shown")
        splashDismissTask?.cancel()
        splashDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                dismissSplash(reason: "timeout")
            }
        }
    }

    private func dismissSplash(reason: String) {
        guard showSplash else { return }
        debugLog(.ui, "splash dismissed reason=\(reason)")
        splashDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.35)) {
            showSplash = false
        }
        if !viewModel.showOnboarding {
            viewModel.recordMainPageEntryIfNeeded()
        }
        presentPendingRatePromptIfPossible()
    }

    private func presentRatePromptIfPossible() {
        guard !showRatePrompt else { return }
        debugLog(.ui, "review prompt showing")
        viewModel.markRatePromptShown()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            showRatePrompt = true
        }
    }

    private func notifyMainPageVisibleIfNeeded() {
        guard scenePhase == .active else { return }
        guard !showSplash, !viewModel.showOnboarding else { return }
        viewModel.recordMainPageEntryIfNeeded()
    }

    private func presentPendingRatePromptIfPossible() {
        guard let token = pendingReviewRequestToken else { return }
        guard !showSplash else {
            debugLog(.ui, "review prompt waiting reason=splash_visible token=\(token)")
            return
        }
        guard !viewModel.showOnboarding else {
            debugLog(.ui, "review prompt waiting reason=onboarding_visible token=\(token)")
            return
        }
        pendingReviewRequestToken = nil
        debugLog(.ui, "review prompt showing token=\(token)")
        presentRatePromptIfPossible()
    }

    private func dismissRatePrompt() {
        withAnimation(.easeOut(duration: 0.22)) {
            showRatePrompt = false
        }
    }
}

private struct FoxSplashView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    FoxTheme.homeStageTop,
                    Color(red: 0.21, green: 0.39, blue: 0.61),
                    FoxTheme.backgroundBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 22) {
                    Text("What Does the Fox Say")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)

                    VStack(spacing: 8) {
                        Text("Lucia Du")
                        Text("Juno Li")
                    }
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))

                    Text("A multilingual speaking coach with a fox who actually talks back.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineSpacing(3)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 30)
                .background(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 24)

                Spacer()

                Text("Tap to continue")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.bottom, 42)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("What Does the Fox Say")
        .accessibilityValue("Created by Lucia Du and Juno Li")
        .accessibilityHint("Double tap to continue into the app.")
    }
}

private struct FoxRatePromptView: View {
    let onRateNow: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        ZStack {
            FoxTheme.modalBackdrop
                .ignoresSafeArea()

            FoxCenteredPromptCard(
                accent: FoxTheme.accent,
                symbol: "star.fill",
                title: "Enjoying practice with the fox?",
                message: "If the app is helping you speak more often, we'd love a quick rating."
            ) {
                HStack(spacing: 12) {
                    promptSecondaryButton(title: "Not Now", action: onNotNow)
                    promptPrimaryButton(title: "Rate Now", tint: FoxTheme.accent, action: onRateNow)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

private struct FoxCenteredPromptCard<Actions: View>: View {
    let accent: Color
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(accent)
                }

                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.82))
                .lineSpacing(4)

            actions
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 28, y: 16)
        )
        .padding(.horizontal, 24)
    }
}

private func promptSecondaryButton(title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
        .font(.headline.weight(.semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
}

private func promptPrimaryButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
        .font(.headline.weight(.semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(
            Capsule()
                .fill(tint.opacity(0.86))
                .overlay(
                    Capsule()
                        .stroke(tint.opacity(0.24), lineWidth: 1)
                )
        )
}

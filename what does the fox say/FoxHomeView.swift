import AVFoundation
import SwiftUI

struct FoxHomeView: View {
    @EnvironmentObject private var viewModel: FoxAppViewModel

    var body: some View {
        ZStack {
            FoxVideoStage(controller: viewModel.video)

            TapCaptureView { location, size in
                viewModel.handleTap(location: location, in: size)
            }
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                topGlassPanel
                Spacer()
                bottomGlassPanel
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                topBar
                Spacer()
                bottomControls
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 18)

            if let banner = viewModel.micPermissionBannerText {
                VStack {
                    Spacer()
                    Text(banner)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.52), in: Capsule())
                }
                .padding(.bottom, 120)
                .padding(.horizontal, 20)
            }
        }
        .sheet(isPresented: $viewModel.showSettings) {
            FoxSettingsView(profile: viewModel.profile) { updated in
                viewModel.updateProfile(updated)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $viewModel.showHistory) {
            FoxHistoryView()
                .environmentObject(viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.clear)
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            HStack(spacing: 10) {
                Button {
                    viewModel.showHistory = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(glassCircleBackground)

                        if viewModel.hasUnreadHistory {
                            Circle()
                                .fill(FoxTheme.historyDot)
                                .frame(width: 9, height: 9)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("History")
                .accessibilityValue(viewModel.hasUnreadHistory ? "New items available" : "No new items")
                .accessibilityHint("Opens practice history.")

                Button {
                    viewModel.showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(glassCircleBackground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .accessibilityHint("Opens language and persona settings.")
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    viewModel.playEmotion(.lovebunny)
                } label: {
                    Text("😍")
                        .font(.system(size: 21))
                        .frame(width: 42, height: 42)
                        .background(glassCircleBackground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Love bunny animation")
                .accessibilityHint("Plays the love bunny fox animation.")

                Button {
                    viewModel.playEmotion(.scareoffduolingo)
                } label: {
                    Text("😎")
                        .font(.system(size: 21))
                        .frame(width: 42, height: 42)
                        .background(glassCircleBackground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sunglasses animation")
                .accessibilityHint("Plays the sunglasses fox animation.")
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 26) {
                glassActionButton(systemName: "xmark") {
                    viewModel.resetToIdle()
                }
                .accessibilityLabel("Reset")
                .accessibilityHint("Returns the fox to the idle state.")

                RippleButton(
                    isActive: viewModel.isProcessingAudio,
                    action: { viewModel.startListening() },
                    content: {
                        ZStack {
                            glassActionBackground(tint: Color.white.opacity(0.14))
                            Image(systemName: "waveform")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    },
                    size: 58
                )
                .buttonStyle(.plain)
                .accessibilityLabel("Listening status")
                .accessibilityValue(viewModel.isProcessingAudio ? "Active" : "Idle")
                .accessibilityHint("Shows when speech is being processed.")

                glassActionButton(
                    systemName: viewModel.micEnabled ? "mic.fill" : "mic.slash.fill",
                    tint: viewModel.micEnabled ? FoxTheme.historyDot.opacity(0.9) : FoxTheme.historyDot.opacity(0.72)
                ) {
                    viewModel.toggleMic()
                }
                .accessibilityLabel(viewModel.micEnabled ? "Stop microphone" : "Start microphone")
                .accessibilityValue(viewModel.micEnabled ? "Microphone on" : "Microphone off")
                .accessibilityHint("Starts or stops a speaking practice session.")
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
        }
    }

    private func glassActionButton(
        systemName: String,
        tint: Color = Color.white.opacity(0.14),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                glassActionBackground(tint: tint)
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
        }
        .buttonStyle(.plain)
    }

    private var glassCircleBackground: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(0.1))
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }

    private func glassActionBackground(tint: Color) -> some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(
                Circle()
                    .fill(tint)
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }

    private var topGlassPanel: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(FoxTheme.topFade)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(FoxTheme.homeTopPanelStroke)
                    .frame(height: 1)
            }
            .mask(
                LinearGradient(
                    colors: [Color.white, Color.white.opacity(0.7), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 150)
    }

    private var bottomGlassPanel: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(FoxTheme.bottomFade)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(FoxTheme.homeBottomPanelStroke)
                    .frame(height: 1)
            }
            .mask(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.58), Color.white],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 170)
    }
}

private struct FoxVideoStage: View {
    @ObservedObject var controller: VideoPlaybackController

    var body: some View {
        ZStack {
            FoxTheme.homeStageGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                FoxTheme.homeTopGlow
                    .frame(height: 210)
                    .blur(radius: 36)
                Spacer()
                FoxTheme.homeBottomGlow
                    .frame(height: 280)
                    .blur(radius: 44)
            }
            .ignoresSafeArea()

            DualVideoPlayerView(controller: controller, videoGravity: .resizeAspect)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                FoxTheme.homeTopMask
                    .frame(height: 140)
                Spacer()
                FoxTheme.homeBottomMask
                    .frame(height: 170)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                FoxTheme.homeGlassMistTop
                    .frame(height: 150)
                    .background(.ultraThinMaterial.opacity(0.12))
                    .mask(
                        LinearGradient(
                            colors: [Color.white, Color.white.opacity(0.45), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Spacer()
                FoxTheme.homeGlassMistBottom
                    .frame(height: 170)
                    .background(.ultraThinMaterial.opacity(0.12))
                    .mask(
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.42), Color.white],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }
}

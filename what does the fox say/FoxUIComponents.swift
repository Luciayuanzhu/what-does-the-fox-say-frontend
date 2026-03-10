import SwiftUI

struct TapCaptureView: View {
    var onTap: (CGPoint, CGSize) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            onTap(value.location, proxy.size)
                        }
                )
        }
        .ignoresSafeArea()
    }
}

struct RippleButton<Content: View>: View {
    let isActive: Bool
    let action: () -> Void
    let content: () -> Content
    var size: CGFloat = 56

    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: size, height: size)
                .overlay {
                    if isActive {
                        Circle()
                            .stroke(FoxTheme.accent.opacity(0.40), lineWidth: 2)
                            .scaleEffect(pulse ? 1.85 : 1.0)
                            .opacity(pulse ? 0.0 : 1.0)
                            .animation(.easeOut(duration: 1.15).repeatForever(autoreverses: false), value: pulse)
                    }
                }
        }
        .onAppear {
            pulse = isActive
        }
        .onChange(of: isActive) { _, active in
            pulse = active
        }
    }
}

struct FoxSheetPrimaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.black.opacity(0.78))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct FoxSheetGhostCircleButton: View {
    let systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

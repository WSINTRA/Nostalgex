import SwiftUI
import Combine

/// How strong retro mode looks, in the guide and in full screen alike. Picked on a living
/// room TV on 2026-10-18 from three trial looks: the old one (scanlines 0.12, and none in
/// full screen, which read as too subtle), this one, and a stronger one. The Roku port
/// matches these numbers.
enum RetroLook {
    static let scanlineOpacity = 0.18
    static let cornerShadow = 0.78
    static let topBottomShadow = 0.58
    static let sideShadow = 0.48
    /// Chance per 80 ms tick that the scanlines dip, and how far.
    static let flickerChance = 0.08
    static let flickerRange = 0.76...0.88
    /// Chance that a tracking line runs at each 6 to 15 s check, and its brightness.
    static let glitchChance = 0.45
    static let glitchBrightness = 0.22
}

/// CRT + VHS effect overlay: scanlines, vignette, flicker, tracking glitch.
struct CRTOverlayView: View {
    @State private var flickerOpacity: Double = 1.0
    @State private var trackingOffset: CGFloat = -200
    @State private var showTracking: Bool = false
    @State private var trackingTimer: Timer?
    let flickerTimer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Scanlines
            ScanlineLayer(opacity: RetroLook.scanlineOpacity)
                .opacity(flickerOpacity)

            // VHS tracking glitch line
            if showTracking {
                TrackingGlitchLine(yOffset: trackingOffset, brightness: RetroLook.glitchBrightness)
            }

            // Vignette (dark edges, simulates tube curvature)
            VignetteLayer()

            // Screen edge glow
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.04), lineWidth: 2)
        }
        .allowsHitTesting(false)
        .onReceive(flickerTimer) { _ in
            let roll = Double.random(in: 0...1)
            if roll > 1 - RetroLook.flickerChance {
                withAnimation(.easeInOut(duration: 0.03)) {
                    flickerOpacity = Double.random(in: RetroLook.flickerRange)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    withAnimation(.easeInOut(duration: 0.03)) {
                        flickerOpacity = 1.0
                    }
                }
            }
        }
        .onAppear {
            scheduleNextGlitch()
        }
        .onDisappear {
            trackingTimer?.invalidate()
        }
    }

    private func scheduleNextGlitch() {
        let delay = Double.random(in: 6...15)
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            Task { @MainActor in
                let roll = Double.random(in: 0...1)
                if roll > 1 - RetroLook.glitchChance {
                    triggerGlitch()
                }
                scheduleNextGlitch()
            }
        }
    }

    private func triggerGlitch() {
        let duration = Double.random(in: 0.5...1.5)
        let travel = CGFloat.random(in: 150...400)
        trackingOffset = CGFloat.random(in: -200...200)
        showTracking = true
        withAnimation(.linear(duration: duration)) {
            trackingOffset += travel
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            showTracking = false
        }
    }
}

// MARK: - Scanline layer

private struct ScanlineLayer: View {
    let opacity: Double

    var body: some View {
        Canvas { context, size in
            // Horizontal scanlines every 3px
            let spacing: CGFloat = 3
            var y: CGFloat = 0
            while y < size.height {
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(.black.opacity(opacity)), lineWidth: 1.5)
                y += spacing
            }
        }
    }
}

// MARK: - Vignette layer

private struct VignetteLayer: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Corner shadows (heavier than edges)
                RadialGradient(
                    gradient: Gradient(colors: [.clear, .clear, .black.opacity(RetroLook.cornerShadow)]),
                    center: .center,
                    startRadius: min(w, h) * 0.3,
                    endRadius: max(w, h) * 0.7
                )

                // Top/bottom edge darkening
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(RetroLook.topBottomShadow), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: h * 0.08)

                    Spacer()

                    LinearGradient(
                        colors: [.clear, .black.opacity(RetroLook.topBottomShadow)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: h * 0.08)
                }

                // Left/right edge darkening
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(RetroLook.sideShadow), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: w * 0.06)

                    Spacer()

                    LinearGradient(
                        colors: [.clear, .black.opacity(RetroLook.sideShadow)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: w * 0.06)
                }
            }
        }
    }
}

// MARK: - VHS tracking glitch line

private struct TrackingGlitchLine: View {
    let yOffset: CGFloat
    let brightness: Double

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Thin bright distortion band
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(brightness * 0.53),
                                .white.opacity(brightness),
                                .white.opacity(brightness * 0.53),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 12)

                // Thicker warped band beneath
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(brightness * 0.2),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 30)
            }
            .offset(y: geo.size.height * 0.5 + yOffset)
        }
    }
}

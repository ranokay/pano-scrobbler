import Core
import SwiftUI

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Accent Colors

enum AccentColors {
    static let primary = Color(hue: 0.73, saturation: 0.65, brightness: 0.95)      // Indigo
    static let secondary = Color(hue: 0.78, saturation: 0.55, brightness: 0.90)    // Purple
    static let gradient = LinearGradient(
        colors: [primary, secondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let success = Color(hue: 0.38, saturation: 0.70, brightness: 0.75)      // Green
    static let warning = Color(hue: 0.10, saturation: 0.75, brightness: 0.95)      // Amber
    static let error = Color(hue: 0.0, saturation: 0.70, brightness: 0.85)         // Red

    static let lastFM = Color(hue: 0.0, saturation: 0.75, brightness: 0.85)        // Red
    static let listenBrainz = Color(hue: 0.08, saturation: 0.80, brightness: 0.95) // Orange
    static let file = Color(hue: 0.58, saturation: 0.60, brightness: 0.85)         // Teal
    static let pleroma = Color(hue: 0.73, saturation: 0.50, brightness: 0.80)      // Indigo

    static func serviceColor(for type: Core.AccountType) -> Color {
        switch type {
        case .lastFM, .libreFM, .gnuFM: lastFM
        case .listenBrainz, .customListenBrainz: listenBrainz
        case .pleroma: pleroma
        case .file: file
        }
    }
}

// MARK: - Typography

extension Font {
    static let displayLarge = Font.system(size: 22, weight: .bold, design: .rounded)
    static let displaySmall = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let metricValue = Font.system(size: 20, weight: .bold, design: .rounded)
    static let metricLabel = Font.system(size: 11, weight: .medium, design: .rounded)
    static let logEntry = Font.system(size: 12, weight: .regular, design: .monospaced)
}

// MARK: - Glass Card

struct GlassCard<Content: View>: View {
    var spacing: CGFloat = Spacing.md
    @ViewBuilder var content: () -> Content

    @ViewBuilder
    var body: some View {
        let base = content()
            .padding(spacing)
            .frame(maxWidth: .infinity, alignment: .leading)

        if #available(macOS 26.0, *) {
            base.glassEffect(.regular, in: .rect(cornerRadius: 10))
        } else {
            base
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1)
                }
        }
    }
}

// MARK: - Animated Equalizer

struct AnimatedEqualizer: View {
    var isPlaying: Bool
    var barCount: Int = 3
    var color: Color = AccentColors.primary

    @State private var phases: [CGFloat] = []

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color.gradient)
                    .frame(width: 4, height: isPlaying ? phases[safe: index] ?? 8 : 6)
                    .animation(
                        isPlaying
                            ? .easeInOut(duration: Double.random(in: 0.3...0.6))
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.12)
                            : .easeOut(duration: 0.3),
                        value: isPlaying
                    )
            }
        }
        .frame(height: 24)
        .onAppear {
            phases = (0..<barCount).map { _ in CGFloat.random(in: 8...24) }
        }
        .onChange(of: isPlaying) {
            if isPlaying {
                withAnimation {
                    phases = (0..<barCount).map { _ in CGFloat.random(in: 8...24) }
                }
            }
        }
    }
}

// MARK: - Pulsing Dot

struct PulsingDot: View {
    var color: Color
    var size: CGFloat = 8
    var isPulsing: Bool = true

    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .stroke(color.opacity(0.4), lineWidth: 2)
                    .scaleEffect(pulse ? 2.0 : 1.0)
                    .opacity(pulse ? 0.0 : 0.6)
            }
            .onAppear {
                guard isPulsing else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    var count: Int
    var color: Color = AccentColors.primary

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color, in: Capsule())
                .contentTransition(.numericText())
                .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Playback State Helpers

extension PlaybackState {
    var dotColor: Color {
        switch self {
        case .playing: AccentColors.success
        case .paused: AccentColors.warning
        case .stopped: AccentColors.error
        case .none, .waiting: .secondary
        }
    }

    var displayLabel: String {
        switch self {
        case .playing: "Scrobbling"
        case .paused: "Paused"
        case .stopped: "Stopped"
        case .none: "Idle"
        case .waiting: "Waiting"
        }
    }
}

// MARK: - Collection Safe Subscript

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

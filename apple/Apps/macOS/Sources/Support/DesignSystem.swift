import AppKit
import Core
import Services
import SwiftUI

// MARK: - Layout

/// Minimal layout constants. Most spacing should come from container defaults
/// (Form, List, GroupBox, Section) — only use these where SwiftUI does not
/// already provide native spacing.
enum Layout {
    /// Window-edge padding for plain ScrollView content. Matches macOS HIG.
    static let windowPadding: CGFloat = 20
    /// Vertical gap between major sections inside a ScrollView.
    static let sectionSpacing: CGFloat = 16
    /// Inline gap inside a card / row.
    static let inlineSpacing: CGFloat = 8
    /// Corner radius for hero / surface treatments.
    static let cornerRadius: CGFloat = 12
}

// MARK: - Service Colors

/// Tinted accents for distinguishing services. Mapped to system-named colors
/// so they remain legible against any window material in light/dark mode.
enum ServiceTint {
    static func color(for type: Core.AccountType) -> Color {
        switch type {
        case .lastFM, .libreFM, .gnuFM: .red
        case .listenBrainz, .customListenBrainz: .orange
        case .pleroma: .indigo
        case .file: .teal
        }
    }
}

// MARK: - Adaptive Glass Surfaces

/// Container that opts in to `GlassEffectContainer` on macOS 26+ for
/// merged glass blending. Passes through on classic.
struct AdaptiveGlassContainer<Content: View>: View {
    var spacing: CGFloat = Layout.sectionSpacing
    @ViewBuilder var content: () -> Content

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

extension View {
    /// Wraps the receiver in a glass-aware container on macOS 26.
    @ViewBuilder
    func adaptiveGlassContainer(spacing: CGFloat = Layout.sectionSpacing) -> some View {
        AdaptiveGlassContainer(spacing: spacing) { self }
    }

    /// Window-level background. On macOS 26 this lights up the full Liquid
    /// Glass window chrome; on macOS 15 it leaves the default vibrancy intact.
    @ViewBuilder
    func adaptiveWindowBackground() -> some View {
        if #available(macOS 26.0, *) {
            self.containerBackground(.thinMaterial, for: .window)
        } else {
            self
        }
    }

    /// Hero surface treatment for prominent cards (Now Playing, MusicEntryInfo
    /// header, Onboarding panels, Random result). On macOS 26 uses interactive
    /// glass; on macOS 15 uses a subtle material with a quaternary stroke.
    @ViewBuilder
    func heroGlass(cornerRadius: CGFloat = Layout.cornerRadius) -> some View {
        if #available(macOS 26.0, *) {
            self
                .padding(Layout.sectionSpacing)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .padding(Layout.sectionSpacing)
                .background(.background.tertiary, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1)
                }
        }
    }

    /// Glass treatment for interactive surfaces that aren't a button (e.g.
    /// a custom search field or pill container).
    @ViewBuilder
    func interactiveGlass(cornerRadius: CGFloat = 8) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1)
                }
        }
    }

    /// Prefer this for primary buttons. On macOS 26 uses `glassProminent`;
    /// on macOS 15 falls back to `.borderedProminent`.
    @ViewBuilder
    func prominentGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// For secondary buttons. macOS 26 → `.glass`; macOS 15 → `.bordered`.
    @ViewBuilder
    func standardGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

// MARK: - Artwork Cache Environment

private struct ArtworkCacheKey: EnvironmentKey {
    static let defaultValue: ArtworkCache = ArtworkCache()
}

extension EnvironmentValues {
    var artworkCache: ArtworkCache {
        get { self[ArtworkCacheKey.self] }
        set { self[ArtworkCacheKey.self] = newValue }
    }
}

extension View {
    func artworkCache(_ cache: ArtworkCache) -> some View {
        environment(\.artworkCache, cache)
    }
}

// MARK: - AsyncArtwork

/// Resolves artwork via `ArtworkCache` and displays it with a graceful
/// placeholder. Use this for artist / album / track artwork everywhere the
/// raw Last.fm `imageURL` would otherwise be a deprecated placeholder.
struct AsyncArtwork: View {
    var subject: ArtworkCache.Subject
    var hint: URL?
    var placeholderSymbol: String
    var cornerRadius: CGFloat = 6

    @Environment(\.artworkCache) private var cache
    @State private var resolved: URL?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: taskID) {
            await MainActor.run {
                self.resolved = nil
                self.image = nil
            }
            let url = await cache.resolve(subject, hint: hint)
            guard let url, let data = await cache.imageData(for: url), let image = NSImage(data: data) else {
                await MainActor.run {
                    self.resolved = url
                    self.image = nil
                }
                return
            }
            await MainActor.run {
                self.resolved = url
                self.image = image
            }
        }
    }

    private var taskID: String {
        "\(subject)|\(hint?.absoluteString ?? "")"
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.background.tertiary)
            .overlay {
                Image(systemName: placeholderSymbol)
                    .foregroundStyle(.tertiary)
            }
    }
}

// MARK: - CollapsibleGroupBox

/// A GroupBox-styled container with a clickable header that toggles disclosure.
/// Unlike `DisclosureGroup`, the entire title row is a hit target, not just
/// the chevron.
struct CollapsibleGroupBox<Label: View, Content: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var label: () -> Label
    @ViewBuilder var content: () -> Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: Layout.inlineSpacing) {
                        label()
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    content()
                        .padding(.top, Layout.inlineSpacing)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

// MARK: - Animated Equalizer

/// Three-bar VU indicator used in the Now Playing hero.
struct AnimatedEqualizer: View {
    var isPlaying: Bool
    var barCount: Int = 3
    var color: Color = .accentColor

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

/// Small status indicator with an optional pulse animation.
struct PulsingDot: View {
    var color: Color
    var size: CGFloat = 8
    var isPulsing: Bool = true

    @State private var pulse = false

    var body: some View {
        ZStack {
            if isPulsing {
                Circle()
                    .stroke(color.opacity(0.4), lineWidth: 2)
                    .scaleEffect(pulse ? 2.0 : 1.0)
                    .opacity(pulse ? 0.0 : 0.6)
            }

            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 2, height: size * 2)
        .onAppear {
            updatePulse()
        }
        .onChange(of: isPulsing) {
            updatePulse()
        }
    }

    private func updatePulse() {
        if isPulsing {
            pulse = false
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
        } else {
            pulse = false
        }
    }
}

// MARK: - Playback State Helpers

extension PlaybackState {
    /// Semantic system color for the indicator.
    var indicatorColor: Color {
        switch self {
        case .playing: .green
        case .paused, .stopped, .none, .waiting: .secondary
        }
    }

    var displayLabel: String {
        switch self {
        case .playing: "Scrobbling"
        case .paused, .stopped, .none, .waiting: "Idle"
        }
    }
}

// MARK: - Flow Layout

/// A simple flow layout that wraps children onto new lines.
struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        computeLayout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let result = computeLayout(
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height),
            subviews: subviews
        )
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize.unspecified
            )
        }
    }

    private struct FlowLayoutResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> FlowLayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }

        return FlowLayoutResult(
            size: CGSize(width: maxWidth, height: totalHeight),
            positions: positions
        )
    }
}

// MARK: - Collection Safe Subscript

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

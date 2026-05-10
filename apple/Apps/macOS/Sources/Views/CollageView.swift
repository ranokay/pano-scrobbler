import SwiftUI
import Core
import Services
import AppKit

/// Generates an NxN artwork collage from top charts — analogous to Kotlin CollageGeneratorVM.
struct CollageView: View {
    @ObservedObject var model: AppModel
    @State private var gridSize = 3
    @State private var chartType: ChartType = .albums
    @State private var period: LastFMPeriod = .month
    @State private var showCaptions = true
    @State private var isGenerating = false
    @State private var generatedImage: NSImage?
    @State private var error: String?
    @State private var progress: Double = 0

    enum ChartType: String, CaseIterable {
        case artists = "Artists"
        case albums = "Albums"
        case tracks = "Tracks"

        var icon: String {
            switch self {
            case .artists: "person.fill"
            case .albums: "square.stack"
            case .tracks: "music.note"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                controls
                previewSection
            }
            .padding(Spacing.lg)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Collage Generator")
                .font(.displayLarge)
            Text("Create artwork collages from your top charts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                // Type
                Picker("Type", selection: $chartType) {
                    ForEach(ChartType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type.icon).tag(type)
                    }
                }
                .frame(width: 140)

                // Period
                Picker("Period", selection: $period) {
                    ForEach(LastFMPeriod.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .frame(width: 140)

                // Grid size
                Picker("Grid", selection: $gridSize) {
                    Text("3×3").tag(3)
                    Text("4×4").tag(4)
                    Text("5×5").tag(5)
                }
                .frame(width: 100)

                Toggle("Captions", isOn: $showCaptions)
            }

            HStack(spacing: Spacing.md) {
                Button {
                    Task { await generateCollage() }
                } label: {
                    Label("Generate", systemImage: "paintbrush.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)

                if generatedImage != nil {
                    Button {
                        saveCollage()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        shareCollage()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        copyCollage()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        if isGenerating {
            VStack(spacing: Spacing.md) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text("Generating collage…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
        } else if let error {
            ContentUnavailableView(
                "Generation Failed",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
        } else if let image = generatedImage {
            VStack(spacing: Spacing.sm) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 600, maxHeight: 600)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)

                Text("\(gridSize)×\(gridSize) \(chartType.rawValue) • \(period.displayName)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        } else {
            VStack(spacing: Spacing.md) {
                Spacer(minLength: 60)
                Image(systemName: "photo.artframe")
                    .font(.system(size: 48))
                    .foregroundStyle(.quaternary)
                Text("Configure options and press Generate")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 60)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Generation

    private func generateCollage() async {
        guard let service = model.lastFMService else {
            error = "No Last.fm account connected."
            return
        }

        isGenerating = true
        error = nil
        generatedImage = nil
        progress = 0

        do {
            let limit = gridSize * gridSize

            // Fetch chart entries
            let artworkURLs: [(url: URL?, name: String, subtitle: String?)]
            switch chartType {
            case .artists:
                let response = try await service.getTopArtists(period: period, limit: limit)
                artworkURLs = response.entries.map { ($0.imageURL, $0.name, nil) }
            case .albums:
                let response = try await service.getTopAlbums(period: period, limit: limit)
                artworkURLs = response.entries.map { ($0.imageURL, $0.name, $0.artist?.name) }
            case .tracks:
                let response = try await service.getTopTracks(period: period, limit: limit)
                artworkURLs = response.entries.map { ($0.imageURL, $0.name, $0.artist.name) }
            }

            progress = 0.2

            // Download artwork images
            let cellSize = 300
            let totalSize = cellSize * gridSize
            var images: [(NSImage, String, String?)] = []

            for (index, entry) in artworkURLs.prefix(limit).enumerated() {
                var img: NSImage?
                if let url = entry.url {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    img = NSImage(data: data)
                }

                if img == nil {
                    // Create placeholder
                    img = createPlaceholder(size: cellSize, type: chartType)
                }

                images.append((img!, entry.name, entry.subtitle))
                progress = 0.2 + 0.6 * Double(index + 1) / Double(min(limit, artworkURLs.count))
            }

            // Draw collage with CoreGraphics
            let nsImage = NSImage(size: NSSize(width: totalSize, height: totalSize))
            nsImage.lockFocus()

            guard let context = NSGraphicsContext.current?.cgContext else {
                nsImage.unlockFocus()
                error = "Could not create graphics context."
                isGenerating = false
                return
            }

            // Flip coordinate system
            context.translateBy(x: 0, y: CGFloat(totalSize))
            context.scaleBy(x: 1, y: -1)

            for (index, (image, name, subtitle)) in images.enumerated() {
                let col = index % gridSize
                let row = index / gridSize
                let x = CGFloat(col * cellSize)
                let y = CGFloat(row * cellSize)
                let rect = CGRect(x: x, y: y, width: CGFloat(cellSize), height: CGFloat(cellSize))

                // Draw image
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    context.draw(cgImage, in: rect)
                }

                // Draw captions
                if showCaptions {
                    drawCaption(context: context, name: name, subtitle: subtitle, rect: rect, cellSize: cellSize)
                }
            }

            nsImage.unlockFocus()
            progress = 1.0

            withAnimation(.spring(duration: 0.3)) {
                generatedImage = nsImage
            }
            isGenerating = false

        } catch {
            self.error = error.localizedDescription
            isGenerating = false
        }
    }

    private func drawCaption(context: CGContext, name: String, subtitle: String?, rect: CGRect, cellSize: Int) {
        let padding: CGFloat = 12
        let bottomY = rect.maxY - padding

        // Draw semi-transparent gradient background
        let gradientRect = CGRect(x: rect.minX, y: rect.maxY - CGFloat(cellSize) * 0.4, width: rect.width, height: CGFloat(cellSize) * 0.4)
        let colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.7)]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
            context.saveGState()
            context.clip(to: gradientRect)
            context.drawLinearGradient(gradient, start: CGPoint(x: gradientRect.midX, y: gradientRect.minY), end: CGPoint(x: gradientRect.midX, y: gradientRect.maxY), options: [])
            context.restoreGState()
        }

        // Draw text
        let nameFont = NSFont.boldSystemFont(ofSize: 14)
        let subtitleFont = NSFont.systemFont(ofSize: 12)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)

        var textY = bottomY

        if let subtitle {
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
                .shadow: shadow
            ]
            let subtitleStr = NSAttributedString(string: subtitle, attributes: subtitleAttrs)
            let subtitleSize = subtitleStr.size()
            textY -= subtitleSize.height
            subtitleStr.draw(at: NSPoint(x: rect.minX + padding, y: textY))
        }

        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: nameFont,
            .foregroundColor: NSColor.white,
            .shadow: shadow
        ]
        let nameStr = NSAttributedString(string: name, attributes: nameAttrs)
        let nameSize = nameStr.size()
        textY -= nameSize.height
        nameStr.draw(at: NSPoint(x: rect.minX + padding, y: textY))
    }

    private func createPlaceholder(size: Int, type: ChartType) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        NSColor(white: 0.15, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()

        let iconName: String
        switch type {
        case .artists: iconName = "person.fill"
        case .albums: iconName = "square.stack"
        case .tracks: iconName = "music.note"
        }

        if let symbolImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: CGFloat(size) / 4, weight: .light)
            let configured = symbolImage.withSymbolConfiguration(config) ?? symbolImage
            let iconSize = configured.size
            let origin = NSPoint(x: CGFloat(size - Int(iconSize.width)) / 2, y: CGFloat(size - Int(iconSize.height)) / 2)
            configured.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 0.3)
        }

        image.unlockFocus()
        return image
    }

    // MARK: - Actions

    private func saveCollage() {
        guard let image = generatedImage else { return }
        let panel = NSSavePanel()
        panel.title = "Save Collage"
        panel.nameFieldStringValue = "collage-\(chartType.rawValue.lowercased())-\(gridSize)x\(gridSize).png"
        panel.allowedContentTypes = [.png]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: url)
        }
    }

    private func shareCollage() {
        guard let image = generatedImage else { return }
        let picker = NSSharingServicePicker(items: [image])
        if let window = NSApp.mainWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    private func copyCollage() {
        guard let image = generatedImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}

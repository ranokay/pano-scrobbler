import AppKit
import Core
import Services
import SwiftUI

/// Generates an NxN artwork collage from top charts.
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
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                controlsCard
                actionsRow
                previewSection
            }
            .padding(Layout.windowPadding)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Controls

    private var controlsCard: some View {
        GroupBox("Options") {
            Grid(alignment: .leading, horizontalSpacing: Layout.sectionSpacing, verticalSpacing: 10) {
                GridRow {
                    Text("Type").foregroundStyle(.secondary)
                    Picker("Type", selection: $chartType) {
                        ForEach(ChartType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Period").foregroundStyle(.secondary)
                    Picker("Period", selection: $period) {
                        ForEach(LastFMPeriod.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Grid").foregroundStyle(.secondary)
                    Picker("Grid", selection: $gridSize) {
                        Text("3 × 3").tag(3)
                        Text("4 × 4").tag(4)
                        Text("5 × 5").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }
                GridRow {
                    Text("Captions").foregroundStyle(.secondary)
                    Toggle("Show captions", isOn: $showCaptions)
                        .labelsHidden()
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: Layout.inlineSpacing) {
            Button {
                Task { await generateCollage() }
            } label: {
                Label("Generate", systemImage: "paintbrush.fill")
            }
            .prominentGlassButton()
            .disabled(isGenerating)

            if generatedImage != nil {
                Button {
                    saveCollage()
                } label: {
                    Label("Save…", systemImage: "square.and.arrow.down")
                }

                Button {
                    shareCollage()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Button {
                    copyCollage()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }

            Spacer()
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        if isGenerating {
            VStack(spacing: Layout.sectionSpacing) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text("Generating collage…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if let error {
            ContentUnavailableView(
                "Generation Failed",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
            .padding(.vertical, 40)
        } else if let image = generatedImage {
            VStack(spacing: Layout.inlineSpacing) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 600, maxHeight: 600)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)

                Text("\(gridSize) × \(gridSize) \(chartType.rawValue) • \(period.displayName)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
        } else {
            ContentUnavailableView(
                "No Collage",
                systemImage: "photo.artframe",
                description: Text("Configure options and press Generate.")
            )
            .padding(.vertical, 40)
        }
    }

    // MARK: - Generation

    private func generateCollage() async {
        guard let service = model.lastFMService else {
            error = "No Last.fm account connected."
            return
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)

        isGenerating = true
        error = nil
        generatedImage = nil
        progress = 0

        do {
            let limit = gridSize * gridSize

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

            let cellSize = 300
            let totalSize = cellSize * gridSize
            var images: [(NSImage, String, String?)] = []

            for (index, entry) in artworkURLs.prefix(limit).enumerated() {
                var img: NSImage?
                if let url = entry.url {
                    let (data, _) = try await session.data(from: url)
                    img = NSImage(data: data)
                }

                if img == nil {
                    img = createPlaceholder(size: cellSize, type: chartType)
                }

                images.append((img!, entry.name, entry.subtitle))
                progress = 0.2 + 0.6 * Double(index + 1) / Double(min(limit, artworkURLs.count))
            }

            let nsImage = NSImage(size: NSSize(width: totalSize, height: totalSize))
            nsImage.lockFocus()

            // AppKit's lockFocus context uses a y-up coordinate system. We
            // want row 0 to render at the top, so we invert the y origin
            // when computing each cell's rect — no manual CG transform
            // needed. This also lets NSAttributedString.draw render captions
            // right-side-up.

            for (index, (image, name, subtitle)) in images.enumerated() {
                let col = index % gridSize
                let row = index / gridSize
                let x = CGFloat(col * cellSize)
                // Place row 0 at the top: y origin counts from the bottom of
                // the canvas, so the top-left cell is at y = totalSize - cellSize.
                let y = CGFloat(totalSize - (row + 1) * cellSize)
                let rect = CGRect(x: x, y: y, width: CGFloat(cellSize), height: CGFloat(cellSize))

                image.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)

                if showCaptions, let context = NSGraphicsContext.current?.cgContext {
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
        // y-up AppKit coordinates: rect.minY is the BOTTOM of the cell.
        let padding: CGFloat = 12

        // Gradient: opaque-black at the bottom fading to transparent ~40% up.
        let gradientHeight = CGFloat(cellSize) * 0.4
        let gradientRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: gradientHeight
        )
        let colors = [CGColor(gray: 0, alpha: 0.85), CGColor(gray: 0, alpha: 0)]
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: [0, 1]
        ) {
            context.saveGState()
            context.clip(to: gradientRect)
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: gradientRect.midX, y: gradientRect.minY),  // opaque at bottom
                end: CGPoint(x: gradientRect.midX, y: gradientRect.maxY),    // fades up
                options: []
            )
            context.restoreGState()
        }

        // Text: name on top of subtitle, both anchored just above the bottom.
        let nameFont = NSFont.boldSystemFont(ofSize: 14)
        let subtitleFont = NSFont.systemFont(ofSize: 12)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: 1)

        // In y-up coords, the baseline goes up: subtitle first (y = bottom + padding),
        // then name above it.
        var textY = rect.minY + padding

        if let subtitle {
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
                .shadow: shadow
            ]
            let subtitleStr = NSAttributedString(string: subtitle, attributes: subtitleAttrs)
            let subtitleSize = subtitleStr.size()
            subtitleStr.draw(at: NSPoint(x: rect.minX + padding, y: textY))
            textY += subtitleSize.height + 2
        }

        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: nameFont,
            .foregroundColor: NSColor.white,
            .shadow: shadow
        ]
        let nameStr = NSAttributedString(string: name, attributes: nameAttrs)
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
            let origin = NSPoint(
                x: CGFloat(size - Int(iconSize.width)) / 2,
                y: CGFloat(size - Int(iconSize.height)) / 2
            )
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

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            showSaveError("Could not encode the collage image.")
            return
        }

        do {
            try pngData.write(to: url)
        } catch {
            showSaveError("Could not save collage: \(error.localizedDescription)")
        }
    }

    private func showSaveError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Save Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
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

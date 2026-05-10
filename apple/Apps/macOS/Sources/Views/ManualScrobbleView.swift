import SwiftUI
import Core

/// Allows the user to manually submit a scrobble to all active services.
struct ManualScrobbleView: View {
    @ObservedObject var model: AppModel
    @State private var artist = ""
    @State private var track = ""
    @State private var album = ""
    @State private var albumArtist = ""
    @State private var timestamp = Date()
    @State private var useCustomTimestamp = false
    @State private var isSubmitting = false
    @State private var result: SubmitResult?

    enum SubmitResult {
        case success
        case error(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                formFields
                submitSection
                resultSection
            }
            .padding(Spacing.lg)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Manual Scrobble")
                .font(.displayLarge)
            Text("Manually submit a scrobble to all active services.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Form

    private var formFields: some View {
        GlassCard(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        fieldLabel("Artist", required: true)
                        TextField("Artist name", text: $artist)
                            .textFieldStyle(.roundedBorder)

                        fieldLabel("Track", required: true)
                        TextField("Track name", text: $track)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        fieldLabel("Album", required: false)
                        TextField("Album name (optional)", text: $album)
                            .textFieldStyle(.roundedBorder)

                        fieldLabel("Album Artist", required: false)
                        TextField("Album artist (optional)", text: $albumArtist)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Divider()

                HStack(spacing: Spacing.md) {
                    Toggle("Custom timestamp", isOn: $useCustomTimestamp)

                    if useCustomTimestamp {
                        DatePicker("", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    } else {
                        Text("Will use current time")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }
        }
    }

    private func fieldLabel(_ text: String, required: Bool) -> some View {
        HStack(spacing: 2) {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if required {
                Text("*")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AccentColors.error)
            }
        }
    }

    // MARK: - Submit

    private var submitSection: some View {
        HStack(spacing: Spacing.md) {
            Button {
                Task { await submitScrobble() }
            } label: {
                Label(isSubmitting ? "Submitting…" : "Submit Scrobble", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting || artist.trimmingCharacters(in: .whitespaces).isEmpty || track.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                clearForm()
            } label: {
                Label("Clear", systemImage: "xmark")
            }
            .buttonStyle(.bordered)

            Spacer()

            Text("\(model.accounts.filter(\.enabled).count) active service(s)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var resultSection: some View {
        if let result {
            switch result {
            case .success:
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AccentColors.success)
                    Text("Scrobble submitted successfully!")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AccentColors.success)
                }
                .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))

            case .error(let message):
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AccentColors.error)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(AccentColors.error)
                }
                .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
            }
        }
    }

    // MARK: - Actions

    private func submitScrobble() async {
        isSubmitting = true
        result = nil

        let data = ScrobbleData(
            artist: artist.trimmingCharacters(in: .whitespaces),
            track: track.trimmingCharacters(in: .whitespaces),
            album: album.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            albumArtist: albumArtist.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            duration: nil,
            timestamp: useCustomTimestamp ? timestamp : Date()
        )

        await model.manualScrobble(data)

        withAnimation(.spring(duration: 0.3)) {
            result = .success
        }

        isSubmitting = false

        // Auto-clear after success
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation { result = nil }
        }
    }

    private func clearForm() {
        artist = ""
        track = ""
        album = ""
        albumArtist = ""
        timestamp = Date()
        useCustomTimestamp = false
        result = nil
    }
}

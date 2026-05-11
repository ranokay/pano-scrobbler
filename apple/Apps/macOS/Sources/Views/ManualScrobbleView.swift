import Core
import SwiftUI

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
        VStack(spacing: 0) {
            Form {
                Section("Track") {
                    TextField("Artist", text: $artist, prompt: Text("Required"))
                    TextField("Track", text: $track, prompt: Text("Required"))
                }

                Section("Album") {
                    TextField("Album", text: $album)
                    TextField("Album Artist", text: $albumArtist)
                }

                Section("Timing") {
                    Toggle("Custom timestamp", isOn: $useCustomTimestamp)

                    if useCustomTimestamp {
                        DatePicker(
                            "Timestamp",
                            selection: $timestamp,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    } else {
                        LabeledContent("Timestamp", value: "Current time when submitted")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if let result {
                        switch result {
                        case .success:
                            Label("Scrobble submitted successfully!", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .error(let message):
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            footer
        }
        .navigationSubtitle("\(model.accounts.filter(\.enabled).count) active service(s)")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Layout.inlineSpacing) {
            Button {
                clearForm()
            } label: {
                Label("Clear", systemImage: "xmark")
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                Task { await submitScrobble() }
            } label: {
                if isSubmitting {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Submit Scrobble", systemImage: "paperplane.fill")
                }
            }
            .prominentGlassButton()
            .keyboardShortcut(.defaultAction)
            .disabled(
                isSubmitting
                    || artist.trimmingCharacters(in: .whitespaces).isEmpty
                    || track.trimmingCharacters(in: .whitespaces).isEmpty
            )
        }
        .padding(Layout.windowPadding)
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

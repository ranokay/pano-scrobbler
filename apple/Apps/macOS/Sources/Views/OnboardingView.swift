import AppKit
import Core
import SwiftUI

/// First-launch onboarding wizard.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentStep = 0

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            // Step content
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: accountStep
                case 2: permissionStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.spring(duration: 0.4), value: currentStep)

            Divider()

            // Footer: progress + navigation
            HStack(spacing: Layout.sectionSpacing) {
                ProgressView(value: Double(currentStep + 1), total: Double(totalSteps))
                    .progressViewStyle(.linear)
                    .frame(width: 140)
                    .accessibilityLabel("Step \(currentStep + 1) of \(totalSteps)")

                Spacer()

                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .standardGlassButton()
                    .controlSize(.large)
                }

                if currentStep < totalSteps - 1 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .prominentGlassButton()
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get Started") {
                        withAnimation {
                            hasCompletedOnboarding = true
                        }
                    }
                    .prominentGlassButton()
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(Layout.windowPadding)
        }
        .frame(width: 560, height: 460)
        .adaptiveWindowBackground()
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: Layout.sectionSpacing) {
            Spacer()

            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating)

            Text("Welcome to Pano Scrobbler")
                .font(.largeTitle.weight(.semibold))

            Text("Track your music listening across Last.fm, ListenBrainz, and more.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Spacer()
        }
        .padding(Layout.windowPadding)
    }

    private var accountStep: some View {
        VStack(spacing: Layout.sectionSpacing) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Add an Account")
                .font(.title.weight(.semibold))

            Text("Connect a scrobbling service to start tracking your listens.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            GroupBox {
                if model.accounts.isEmpty {
                    Label {
                        Text("No accounts configured yet. You can add them from the Accounts tab after setup.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.orange)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.accounts.filter(\.enabled)) { acct in
                            Label("\(acct.type.displayName): \(acct.username)",
                                  systemImage: "checkmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.green)
                                .font(.callout)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: 400)

            Spacer()
        }
        .padding(Layout.windowPadding)
    }

    private var permissionStep: some View {
        VStack(spacing: Layout.sectionSpacing) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Permissions")
                .font(.title.weight(.semibold))

            Text("Pano Scrobbler uses macOS Automation permission to read now-playing metadata from Music and Spotify.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            GroupBox {
                VStack(alignment: .leading, spacing: Layout.inlineSpacing) {
                    permissionRow(
                        "Automation",
                        description: "Required when Music or Spotify first share now-playing metadata",
                        icon: "applescript"
                    )
                    Divider()
                    permissionRow(
                        "Notifications",
                        description: "Optional — show alerts when tracks are scrobbled",
                        icon: "bell"
                    )
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: 420)

            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            }
            .standardGlassButton()

            Spacer()
        }
        .padding(Layout.windowPadding)
    }

    private func permissionRow(_ title: String, description: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
        }
        .padding(.vertical, 4)
    }
}

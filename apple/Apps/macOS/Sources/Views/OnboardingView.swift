import SwiftUI
import Core

/// First-launch onboarding wizard — analogous to Kotlin's onboarding flow.
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

            // Navigation bar
            HStack {
                // Step dots
                HStack(spacing: 8) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Circle()
                            .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: currentStep)
                    }
                }

                Spacer()

                HStack(spacing: Spacing.md) {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation { currentStep -= 1 }
                        }
                        .buttonStyle(.bordered)
                    }

                    if currentStep < totalSteps - 1 {
                        Button("Next") {
                            withAnimation { currentStep += 1 }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Get Started") {
                            withAnimation {
                                hasCompletedOnboarding = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(Spacing.lg)
        }
        .frame(width: 560, height: 420)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundStyle(.linearGradient(
                    colors: [.purple, .pink, .orange],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .symbolEffect(.pulse, options: .repeating)

            Text("Welcome to Pano Scrobbler")
                .font(.system(size: 28, weight: .bold))

            Text("Track your music listening across Last.fm, ListenBrainz, and more.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Spacer()
        }
        .padding(Spacing.xl)
    }

    private var accountStep: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Add an Account")
                .font(.title2.weight(.semibold))

            Text("Connect your scrobbling service to start tracking.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            VStack(spacing: Spacing.sm) {
                if model.accounts.isEmpty {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.orange)
                        Text("No accounts configured yet. You can add them from the Accounts tab after setup.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(Spacing.md)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    ForEach(model.accounts.filter(\.enabled)) { acct in
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("\(acct.type.displayName): \(acct.username)")
                                .font(.system(size: 13))
                        }
                    }
                }
            }
            .frame(maxWidth: 340)

            Spacer()
        }
        .padding(Spacing.xl)
    }

    private var permissionStep: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Permissions")
                .font(.title2.weight(.semibold))

            Text("Pano Scrobbler needs accessibility access to detect what music apps are playing.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                permissionRow("Accessibility", description: "Required to read now-playing info from media apps", icon: "hand.raised.fill")
                permissionRow("Notifications", description: "Optional — show alerts when tracks are scrobbled", icon: "bell.fill")
            }
            .padding(Spacing.md)
            .frame(maxWidth: 380)

            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(Spacing.xl)
    }

    private func permissionRow(_ title: String, description: String, icon: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

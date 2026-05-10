import AppKit
import Core
import Services
import SwiftUI

struct AccountsView: View {
    @ObservedObject var model: AppModel
    @State private var showingAddSheet = false
    @State private var hoveredID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                accountsList
            }
            .padding(Spacing.lg)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddAccountSheet(model: model)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Accounts")
                    .font(.displayLarge)

                Text("Manage your scrobbling service connections.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showingAddSheet = true
            } label: {
                Label("Add Account", systemImage: "plus")
            }

        }
    }

    // MARK: - Accounts List

    @ViewBuilder
    private var accountsList: some View {
        if model.accounts.isEmpty {
            GlassCard(spacing: Spacing.xl) {
                ContentUnavailableView {
                    Label("No Accounts", systemImage: "person.crop.circle.badge.plus")
                } description: {
                    Text("Add a scrobbling service to get started.")
                } actions: {
                    Button("Add Account") {
                        showingAddSheet = true
                    }

                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xl)
            }
        } else {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(Array(model.accounts.enumerated()), id: \.element.id) { index, account in
                    AccountCard(
                        account: account,
                        isHovered: hoveredID == account.id,
                        onDelete: {
                            withAnimation(.spring(duration: 0.35)) {
                                model.removeAccounts(at: IndexSet(integer: index))
                            }
                        }
                    )
                    .onHover { isHovered in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredID = isHovered ? account.id : nil
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Account Card

private struct AccountCard: View {
    var account: UserAccount
    var isHovered: Bool
    var onDelete: () -> Void

    var body: some View {
        GlassCard(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon(for: account.type))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AccentColors.serviceColor(for: account.type))
                    .frame(width: 32, height: 32)
                    .background {
                        Circle()
                            .fill(AccentColors.serviceColor(for: account.type).opacity(0.12))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.username)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))

                    Text(account.type.displayName)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if account.enabled {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AccentColors.success)
                            .font(.system(size: 14))
                        Text("Active")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AccentColors.success)
                    }
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .opacity(isHovered ? 1 : 0)
            }
        }

    }

    private func icon(for type: AccountType) -> String {
        switch type {
        case .file: "doc.badge.plus"
        case .listenBrainz, .customListenBrainz: "brain.head.profile.fill"
        case .lastFM, .libreFM, .gnuFM: "dot.radiowaves.left.and.right"
        case .pleroma: "network"
        }
    }
}

// MARK: - Add Account Sheet

private struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @State private var accountKind: AccountKind = .lastFM
    @State private var lastFMMode: LastFMLoginMode = .oauth
    @State private var username = ""
    @State private var token = ""
    @State private var apiKey = ""
    @State private var apiSecret = ""
    @State private var sessionKey = ""
    @State private var filePath = ""
    @State private var oauthStatus = ""
    @State private var isAuthenticating = false
    @State private var authError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Add Account")
                .font(.displayLarge)

            Picker("Type", selection: $accountKind) {
                ForEach(AccountKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: accountKind) { _, _ in
                authError = nil
                oauthStatus = ""
            }

            Form {
                switch accountKind {
                case .lastFM:
                    lastFMForm
                case .listenBrainz:
                    TextField("Username", text: $username)
                    SecureField("User token", text: $token)
                case .file:
                    TextField("File path", text: $filePath)
                        .textFieldStyle(.roundedBorder)
                    Button("Use Default JSONL Path") {
                        filePath = model.paths.defaultFileScrobbleURL.path
                    }
                }
            }
            .formStyle(.grouped)

            if let error = authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !oauthStatus.isEmpty {
                HStack(spacing: Spacing.sm) {
                    if isAuthenticating {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(oauthStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(addButtonTitle) {
                    performAdd()
                }
                .disabled(!canAdd || isAuthenticating)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 480)
    }

    // MARK: - Last.fm Form

    @ViewBuilder
    private var lastFMForm: some View {
        Picker("Login Method", selection: $lastFMMode) {
            Text("Browser Login").tag(LastFMLoginMode.oauth)
            Text("Manual Credentials").tag(LastFMLoginMode.manual)
        }
        .pickerStyle(.segmented)

        switch lastFMMode {
        case .oauth:
            SecureField("API Key", text: $apiKey)
            SecureField("API Secret", text: $apiSecret)
            Text("You'll be redirected to Last.fm to authorize.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .manual:
            TextField("Username", text: $username)
            SecureField("API Key", text: $apiKey)
            SecureField("API Secret", text: $apiSecret)
            SecureField("Session Key", text: $sessionKey)
        }
    }

    // MARK: - Add Logic

    private var addButtonTitle: String {
        switch accountKind {
        case .lastFM where lastFMMode == .oauth:
            isAuthenticating ? "Authenticating…" : "Login with Browser"
        default:
            "Add"
        }
    }

    private var canAdd: Bool {
        switch accountKind {
        case .listenBrainz:
            !username.isEmpty && !token.isEmpty
        case .lastFM:
            switch lastFMMode {
            case .oauth:
                !apiKey.isEmpty && !apiSecret.isEmpty
            case .manual:
                !username.isEmpty && !apiKey.isEmpty && !apiSecret.isEmpty && !sessionKey.isEmpty
            }
        case .file:
            !filePath.isEmpty
        }
    }

    private func performAdd() {
        authError = nil

        Task {
            switch accountKind {
            case .listenBrainz:
                await model.addListenBrainzAccount(username: username, token: token)
                dismiss()

            case .lastFM:
                switch lastFMMode {
                case .oauth:
                    isAuthenticating = true
                    do {
                        try await model.authenticateLastFMViaOAuth(
                            apiKey: apiKey,
                            apiSecret: apiSecret,
                            onStatusUpdate: { status in
                                oauthStatus = status
                            }
                        )
                        dismiss()
                    } catch {
                        authError = error.localizedDescription
                    }
                    isAuthenticating = false

                case .manual:
                    await model.addLastFMAccount(
                        username: username,
                        apiKey: apiKey,
                        apiSecret: apiSecret,
                        sessionKey: sessionKey
                    )
                    dismiss()
                }

            case .file:
                await model.addFileAccount(fileURL: URL(fileURLWithPath: filePath))
                dismiss()
            }
        }
    }
}

private enum AccountKind: String, CaseIterable, Identifiable {
    case lastFM
    case listenBrainz
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listenBrainz: "ListenBrainz"
        case .lastFM: "Last.fm"
        case .file: "File"
        }
    }
}

private enum LastFMLoginMode {
    case oauth
    case manual
}

import AppKit
import Core
import Services
import SwiftUI

struct AccountsView: View {
    @ObservedObject var model: AppModel
    @State private var showingAddSheet = false
    @State private var pendingDelete: AccountDeletion?

    private struct AccountDeletion: Identifiable {
        let id = UUID()
        let index: Int
        let account: UserAccount
    }

    var body: some View {
        Group {
            if model.accounts.isEmpty {
                ContentUnavailableView {
                    Label("No Accounts", systemImage: "person.crop.circle.badge.plus")
                } description: {
                    Text("Add a scrobbling service to get started.")
                } actions: {
                    Button("Add Account") {
                        showingAddSheet = true
                    }
                    .prominentGlassButton()
                }
            } else {
                accountsList
            }
        }
        .navigationSubtitle("\(model.accounts.filter(\.enabled).count) active")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddAccountSheet(model: model)
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationBinding,
            presenting: pendingDelete
        ) { deletion in
            Button("Remove Account", role: .destructive) {
                withAnimation {
                    model.removeAccounts(at: IndexSet(integer: deletion.index))
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: { deletion in
            Text("This will remove “\(deletion.account.username)” from \(deletion.account.type.displayName). Scrobble history on the service is unaffected.")
        }
    }

    private var confirmationTitle: String {
        guard let pendingDelete else { return "" }
        return "Remove “\(pendingDelete.account.username)”?"
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    // MARK: - Accounts List

    private var accountsList: some View {
        List {
            ForEach(Array(model.accounts.enumerated()), id: \.element.id) { index, account in
                AccountRow(
                    account: account,
                    onDelete: { pendingDelete = AccountDeletion(index: index, account: account) }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        pendingDelete = AccountDeletion(index: index, account: account)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        pendingDelete = AccountDeletion(index: index, account: account)
                    } label: {
                        Label("Remove Account", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Account Row

private struct AccountRow: View {
    var account: UserAccount
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: Layout.sectionSpacing) {
            Image(systemName: icon(for: account.type))
                .font(.title3)
                .foregroundStyle(ServiceTint.color(for: account.type))
                .frame(width: 32, height: 32)
                .background {
                    Circle().fill(ServiceTint.color(for: account.type).opacity(0.15))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(account.username)
                    .font(.body)

                Text(account.type.displayName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if account.enabled {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .font(.callout)
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove account")
        }
        .padding(.vertical, 4)
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
        VStack(spacing: 0) {
            HStack {
                Text("Add Account")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            }
            .padding(Layout.windowPadding)

            Divider()

            Form {
                Section {
                    Picker("Service", selection: $accountKind) {
                        ForEach(AccountKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: accountKind) { _, _ in
                        authError = nil
                        oauthStatus = ""
                    }
                }

                switch accountKind {
                case .lastFM:
                    lastFMSections
                case .listenBrainz:
                    Section("Credentials") {
                        TextField("Username", text: $username)
                        SecureField("User token", text: $token)
                    }
                case .file:
                    Section("File") {
                        TextField("Path", text: $filePath, prompt: Text("/path/to/scrobbles.jsonl"))
                        Button("Use Default JSONL Path") {
                            filePath = model.paths.defaultFileScrobbleURL.path
                        }
                    }
                }

                if let error = authError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                if !oauthStatus.isEmpty {
                    Section {
                        HStack(spacing: Layout.inlineSpacing) {
                            if isAuthenticating {
                                ProgressView().controlSize(.small)
                            }
                            Text(oauthStatus)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(addButtonTitle) {
                    performAdd()
                }
                .prominentGlassButton()
                .disabled(!canAdd || isAuthenticating)
                .keyboardShortcut(.defaultAction)
            }
            .padding(Layout.windowPadding)
        }
        .frame(width: 520, height: 460)
    }

    // MARK: - Last.fm Sections

    @ViewBuilder
    private var lastFMSections: some View {
        Section {
            Picker("Login Method", selection: $lastFMMode) {
                Text("Browser Login").tag(LastFMLoginMode.oauth)
                Text("Manual Credentials").tag(LastFMLoginMode.manual)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        switch lastFMMode {
        case .oauth:
            Section {
                SecureField("API Key", text: $apiKey)
                SecureField("API Secret", text: $apiSecret)
            } header: {
                Text("API Credentials")
            } footer: {
                Text("You'll be redirected to Last.fm to authorize.")
            }
        case .manual:
            Section("Credentials") {
                TextField("Username", text: $username)
                SecureField("API Key", text: $apiKey)
                SecureField("API Secret", text: $apiSecret)
                SecureField("Session Key", text: $sessionKey)
            }
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
                do {
                    try await model.addListenBrainzAccount(username: username, token: token)
                    dismiss()
                } catch {
                    authError = error.localizedDescription
                }

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
                    do {
                        try await model.addLastFMAccount(
                            username: username,
                            apiKey: apiKey,
                            apiSecret: apiSecret,
                            sessionKey: sessionKey
                        )
                        dismiss()
                    } catch {
                        authError = error.localizedDescription
                    }
                }

            case .file:
                do {
                    try await model.addFileAccount(fileURL: URL(fileURLWithPath: filePath))
                    dismiss()
                } catch {
                    authError = error.localizedDescription
                }
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

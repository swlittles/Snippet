import SwiftUI
import AppKit

/// A secret action waiting for the master password, for items that ask for it again.
struct VaultReprompt: Identifiable {
    let id = UUID()
    var item: VaultItem
    var perform: () -> Void
}

struct VaultSettingsView: View {
    @ObservedObject var vault: VaultStore
    @EnvironmentObject var theme: ThemeStore
    @State private var confirmSignOut = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Show Vault in the launcher", isOn: $vault.enabled).pointerCursor()
            Text("Search a Bitwarden or Vaultwarden vault from the launcher and paste passwords, usernames and verification codes. Vault items are read-only in this version.").font(.caption).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            if vault.state == .signedOut { VaultSignInForm(vault: vault) } else { account }
            if !vault.message.isEmpty { Text(vault.message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack(spacing: 18) {
                Picker("Lock after", selection: $vault.lockMinutes) {
                    Text("1 minute").tag(1); Text("5 minutes").tag(5); Text("15 minutes").tag(15); Text("30 minutes").tag(30); Text("1 hour").tag(60); Text("4 hours").tag(240)
                }.pointerCursor()
                Picker("Clear copied secrets", selection: $vault.clipboardSeconds) {
                    Text("After 15 seconds").tag(15); Text("After 30 seconds").tag(30); Text("After 1 minute").tag(60); Text("After 2 minutes").tag(120); Text("Never").tag(0)
                }.pointerCursor()
            }
            Text("The vault also locks when your Mac sleeps or its screen locks. Your master password is never saved or sent; Snippet sends the server only a derived hash. The encrypted vault is saved on this Mac for offline unlocking; decrypted items stay in memory until the vault locks. Copied secrets are marked confidential so clipboard managers, including Snippet, skip them.").font(.caption).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .alert("Sign out of your vault?", isPresented: $confirmSignOut) {
            Button("Sign out", role: .destructive) { vault.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Snippet removes its saved copy of your encrypted vault and its sign-in tokens from this Mac. Your vault on the server is unchanged.") }
    }
    var account: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: vault.state == .unlocked ? "lock.open" : "lock").font(.system(size: 20)).foregroundStyle(theme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(vault.account?.email ?? "").font(.system(size: 13, weight: .medium))
                    Text(detail).font(.caption).foregroundStyle(theme.secondary)
                }
            }
            HStack {
                if vault.state == .unlocked {
                    Button("Lock now") { vault.lock() }.pointerCursor()
                    Button("Sync now") { Task { await vault.refresh() } }.disabled(vault.busy).pointerCursor()
                } else { Text("Unlock from the Vault section of the launcher.").font(.caption).foregroundStyle(theme.secondary) }
                Spacer()
                Button("Sign out…") { confirmSignOut = true }.pointerCursor()
            }
        }
    }
    var detail: String {
        guard let cache = vault.cache else { return "" }
        let state = vault.state == .unlocked ? "\(vault.items.count) items" : "Locked"
        return [cache.account.server.displayName, state, "synced " + cache.syncedAt.formatted(.relative(presentation: .named))].joined(separator: " · ")
    }
}

struct VaultSignInForm: View {
    @ObservedObject var vault: VaultStore
    @EnvironmentObject var theme: ThemeStore
    @State private var server = VaultServer(kind: .bitwardenUS)
    @State private var email = ""
    @State private var password = ""
    @State private var useAPIKey = false
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var code = ""
    @State private var provider: VaultTwoFactorProvider?
    @State private var remember = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch vault.step {
            case .credentials: credentials
            case .code(let providers): secondFactor(providers.filter(\.supported))
            case .newDevice:
                Text("Confirm this new device").font(.headline)
                Text("Your server emailed a verification code to \(email). Enter it to finish signing in.").font(.caption).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
                codeEntry
            }
        }
        .onAppear { server = vault.lastServer; email = vault.lastEmail }
        .onChange(of: vault.step) { _ in code = ""; provider = nil }
    }
    var credentials: some View {
        Group {
            Text("Sign in").font(.headline)
            Picker("Server", selection: $server.kind) { ForEach(VaultServer.Kind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).pointerCursor()
            if server.kind == .selfHosted { TextField("Server address, e.g. https://vault.example.com", text: $server.url).textFieldStyle(.roundedBorder) }
            TextField("Email", text: $email).textFieldStyle(.roundedBorder).textContentType(.username)
            SecureField("Master password", text: $password).textFieldStyle(.roundedBorder).onSubmit(signIn)
            Toggle("Sign in with a personal API key", isOn: $useAPIKey).pointerCursor()
                .help("Use this if your account uses Duo or a security key for two-step login. Find the key in your web vault under Settings → Security → Keys.")
            if useAPIKey {
                HStack {
                    TextField("client_id", text: $clientID).textFieldStyle(.roundedBorder)
                    SecureField("client_secret", text: $clientSecret).textFieldStyle(.roundedBorder)
                }
                Text("The API key signs you in; your master password still decrypts the vault on this Mac.").font(.caption).foregroundStyle(theme.secondary)
            }
            HStack {
                Spacer()
                if vault.busy { ProgressView().controlSize(.small) }
                Button("Sign in", action: signIn).buttonStyle(.borderedProminent).pointerCursor()
                    .disabled(vault.busy || email.isEmpty || password.isEmpty || (server.kind == .selfHosted && server.url.isEmpty) || (useAPIKey && (clientID.isEmpty || clientSecret.isEmpty)))
            }
        }
    }
    func secondFactor(_ supported: [VaultTwoFactorProvider]) -> some View {
        let selected = provider ?? supported.first
        return Group {
            Text("Two-step login").font(.headline)
            if supported.count > 1 {
                Picker("Method", selection: Binding(get: { selected ?? .authenticator }, set: { provider = $0; code = "" })) { ForEach(supported) { Text($0.title).tag($0) } }.pointerCursor()
            }
            switch selected {
            case .email?: Text("Send a code to your account’s email address, then enter it here.").font(.caption).foregroundStyle(theme.secondary)
            case .yubiKey?: Text("Touch your YubiKey to enter its code.").font(.caption).foregroundStyle(theme.secondary)
            case .some: Text("Enter the 6-digit code from your authenticator app.").font(.caption).foregroundStyle(theme.secondary)
            case nil: EmptyView()
            }
            if selected != nil {
                Toggle("Remember this Mac", isOn: $remember).pointerCursor()
                codeEntry
            }
        }
    }
    var codeEntry: some View {
        HStack {
            TextField("Code", text: $code).textFieldStyle(.roundedBorder).textContentType(.oneTimeCode).onSubmit(submit).frame(width: 180)
            if (provider ?? currentProviders.first) == .email, case .code = vault.step {
                Button("Send code") { Task { await vault.sendEmailCode() } }.disabled(vault.busy).pointerCursor()
            }
            Spacer()
            if vault.busy { ProgressView().controlSize(.small) }
            Button("Cancel") { vault.cancelSignIn() }.pointerCursor()
            Button("Continue", action: submit).buttonStyle(.borderedProminent).disabled(vault.busy || code.isEmpty).pointerCursor()
        }
    }
    var currentProviders: [VaultTwoFactorProvider] { if case .code(let providers) = vault.step { return providers.filter(\.supported) }; return [] }
    func signIn() {
        guard !vault.busy, !password.isEmpty else { return }
        let secret = password, key = useAPIKey ? (id: clientID, secret: clientSecret) : nil
        password = ""
        Task { await vault.signIn(server: server, email: email, password: secret, apiKey: key) }
    }
    func submit() {
        let value = code, method = provider ?? currentProviders.first
        Task { await vault.submit(code: value, provider: method, remember: remember) }
    }
}

/// Every field of an item, with copy buttons. Secrets stay masked until revealed.
struct VaultDetailView: View {
    let item: VaultItem
    /// Copies a value, evaluated when the copy happens so codes are current.
    let use: (@escaping () -> VaultItem.Field?) -> Void
    @EnvironmentObject var theme: ThemeStore
    @State private var revealed: Set<String> = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let field = item.usernameField { row(field) }
                if let field = item.passwordField { row(field) }
                if !item.totp.isEmpty {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let code = item.codeField(at: context.date), let generator = try? TOTP(item.totp) {
                            // The code is shown; copying still goes through the re-prompt when the item asks for it.
                            row(.init(name: code.name, value: code.value, hidden: item.reprompt), note: "\(generator.remaining(at: context.date))s", revealable: false, action: { use { item.codeField() } })
                        } else { row(.init(name: "Verification code", value: "Invalid authenticator key")) }
                    }
                }
                ForEach(Array(item.uris.enumerated()), id: \.offset) { _, uri in row(.init(name: "Website", value: uri)) }
                ForEach(Array(item.fields.enumerated()), id: \.offset) { _, field in row(field) }
                if !item.notes.isEmpty { row(.init(name: "Notes", value: item.notes, hidden: item.reprompt)) }
            }.padding(.horizontal, 20).padding(.vertical, 8)
        }
    }
    func row(_ field: VaultItem.Field, note: String? = nil, revealable: Bool = true, action: (() -> Void)? = nil) -> some View {
        let key = "\(field.name)#\(field.value.hashValue)"
        let visible = !field.hidden || revealed.contains(key)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(field.name).font(.system(size: 11)).foregroundStyle(theme.secondary).frame(width: 118, alignment: .leading).lineLimit(1)
            Group {
                if visible { Text(field.value).textSelection(.enabled) } else { Text("••••••••") }
            }.font(.system(size: 12, design: .monospaced)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            if let note { Text(note).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.secondary) }
            if field.hidden && revealable && !item.reprompt {
                Button { if revealed.contains(key) { revealed.remove(key) } else { revealed.insert(key) } } label: { Image(systemName: visible ? "eye.slash" : "eye") }
                    .buttonStyle(PointerButtonStyle()).help(visible ? "Hide" : "Reveal").accessibilityLabel((visible ? "Hide " : "Reveal ") + field.name)
            }
            Button { if let action { action() } else { use { field } } } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(PointerButtonStyle()).help("Copy " + field.name.lowercased()).accessibilityLabel("Copy " + field.name)
        }
    }
}

struct VaultRepromptView: View {
    let request: VaultReprompt
    @ObservedObject var vault: VaultStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var shortcuts: ShortcutStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var error = ""
    @State private var checking = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Confirm your master password").font(.title2.bold())
            Text("“\(request.item.name)” asks for your master password before its secrets are used.").font(.caption).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            SecureField("Master password", text: $password).textFieldStyle(.roundedBorder).focused($focused).onSubmit(confirm)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(shortcuts[.cancelEditor].swiftUI).pointerCursor()
                Spacer()
                if checking { ProgressView().controlSize(.small) }
                Button("Continue", action: confirm).buttonStyle(.borderedProminent).disabled(password.isEmpty || checking).pointerCursor()
            }
        }.padding(24).frame(width: 420).background(theme.background).foregroundStyle(theme.text).tint(theme.accent)
            .preferredColorScheme(theme.palette.isDark ? .dark : .light).onAppear { focused = true }
    }
    func confirm() {
        guard !password.isEmpty, !checking else { return }
        let value = password
        password = ""; checking = true
        Task { @MainActor in
            let valid = await vault.verify(password: value)
            checking = false
            guard valid else { error = "Incorrect master password."; return }
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { request.perform() }
        }
    }
}

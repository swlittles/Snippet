import AppKit
import Combine
import Security

/// The encrypted vault as returned by `/api/sync`. Every string except IDs and organization names is an EncString.
struct VaultSync: Decodable {
    struct Profile: Decodable { var id: String; var email: String?; var key: String?; var privateKey: String?; var organizations: [Organization]? }
    struct Organization: Decodable { var id: String; var name: String?; var key: String? }
    struct Folder: Decodable { var id: String; var name: String? }
    struct Cipher: Decodable {
        struct URI: Decodable { var uri: String? }
        struct Login: Decodable { var username: String?; var password: String?; var totp: String?; var uris: [URI]? }
        struct Card: Decodable { var cardholderName: String?; var brand: String?; var number: String?; var expMonth: String?; var expYear: String?; var code: String? }
        struct Identity: Decodable {
            var title: String?, firstName: String?, middleName: String?, lastName: String?, company: String?, email: String?, phone: String?, username: String?
            var address1: String?, address2: String?, address3: String?, city: String?, state: String?, postalCode: String?, country: String?
            var ssn: String?, passportNumber: String?, licenseNumber: String?
        }
        struct SSHKey: Decodable { var privateKey: String?; var publicKey: String?; var keyFingerprint: String? }
        struct Field: Decodable { var name: String?; var value: String?; var type: Int? }
        var id: String
        var organizationId: String?
        var folderId: String?
        var type: Int
        var name: String?
        var notes: String?
        var favorite: Bool?
        var reprompt: Int?
        var key: String?
        var deletedDate: String?
        var login: Login?
        var card: Card?
        var identity: Identity?
        var sshKey: SSHKey?
        var fields: [Field]?
    }
    var profile: Profile
    var folders: [Folder]?
    var ciphers: [Cipher]?
}

/// A decrypted vault item. It exists only in memory while the vault is unlocked.
struct VaultItem: Identifiable, Equatable {
    enum Kind: Int { case login = 1, note = 2, card = 3, identity = 4, sshKey = 5 }
    struct Field: Equatable, Hashable { var name: String; var value: String; var hidden = false }
    var id: String
    var kind: Kind
    var name: String
    var notes = ""
    var favorite = false
    /// The item asks for the master password again before revealing secrets.
    var reprompt = false
    var folder: String?
    var organization: String?
    var username = ""
    var password = ""
    var totp = ""
    var uris: [String] = []
    /// Card, identity, SSH key and custom fields, in display order.
    var fields: [Field] = []
    var resultID: UUID { UUID(uuidString: id) ?? UUID(uuid: VaultCrypto.sha256(Data(id.utf8)).withUnsafeBytes { $0.load(as: uuid_t.self) }) }
    var icon: String {
        switch kind { case .login: return "key"; case .note: return "note.text"; case .card: return "creditcard"; case .identity: return "person.text.rectangle"; case .sshKey: return "terminal" }
    }
    /// What Return pastes.
    var primary: Field? {
        switch kind {
        case .login: return !password.isEmpty ? Field(name: "Password", value: password, hidden: true) : !username.isEmpty ? Field(name: "Username", value: username) : nil
        case .note: return notes.isEmpty ? nil : Field(name: "Note", value: notes, hidden: true)
        case .card, .identity, .sshKey:
            let name = kind == .card ? "Number" : kind == .identity ? "Email" : "Public key"
            return fields.first { $0.name == name && !$0.value.isEmpty } ?? fields.first { !$0.value.isEmpty }
        }
    }
    var subtitle: String {
        var parts: [String] = []
        switch kind {
        case .login: parts.append(username.isEmpty ? (hosts.first ?? "Login") : username)
        case .note: parts.append("Secure note")
        case .card: parts.append([value("Brand"), value("Number").map { "•••• " + $0.suffix(4) }].compactMap { $0 }.joined(separator: " ").nonEmpty ?? "Card")
        case .identity: parts.append(value("Name") ?? value("Email") ?? "Identity")
        case .sshKey: parts.append(value("Fingerprint") ?? "SSH key")
        }
        if let folder { parts.append(folder) }
        if let organization { parts.append(organization) }
        return parts.joined(separator: " · ")
    }
    var hosts: [String] { uris.compactMap { URL(string: $0.contains("://") ? $0 : "https://" + $0)?.host } }
    var searchText: String { ([name, username, folder ?? "", organization ?? ""] + hosts).joined(separator: " ") }
    func value(_ name: String) -> String? { fields.first { $0.name == name && !$0.value.isEmpty }?.value }
    var launchURL: URL? {
        uris.lazy.compactMap { URL(string: $0.contains("://") ? $0 : "https://" + $0) }.first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }
}

extension VaultItem {
    /// The current authenticator code, generated when it's used.
    func codeField(at date: Date = Date()) -> Field? {
        guard !totp.isEmpty, let generator = try? TOTP(totp) else { return nil }
        return Field(name: "Verification code", value: generator.code(at: date), hidden: true)
    }
    var usernameField: Field? { username.isEmpty ? nil : Field(name: "Username", value: username) }
    var passwordField: Field? { password.isEmpty ? nil : Field(name: "Password", value: password, hidden: true) }
}

extension String { var nonEmpty: String? { isEmpty ? nil : self } }

enum VaultDecoder {
    struct Opened { var items: [VaultItem]; var failures: Int }
    static func open(_ sync: VaultSync, userKey: VaultKey) throws -> Opened {
        var organizationKeys: [String: VaultKey] = [:], organizationNames: [String: String] = [:]
        if let protected = sync.profile.privateKey, let organizations = sync.profile.organizations, !organizations.isEmpty {
            let privateKey = try VaultCrypto.privateKey(pkcs8: EncString(protected).decrypt(userKey))
            for organization in organizations {
                organizationNames[organization.id] = organization.name
                if let key = organization.key { organizationKeys[organization.id] = try? VaultKey(EncString(key).decrypt(privateKey: privateKey)) }
            }
        }
        var folders: [String: String] = [:]
        for folder in sync.folders ?? [] { folders[folder.id] = try? folder.name.map { try EncString($0).decryptString(userKey) } }
        var items: [VaultItem] = [], failures = 0
        for cipher in sync.ciphers ?? [] where cipher.deletedDate == nil {
            do {
                guard var key = cipher.organizationId.map({ organizationKeys[$0] }) ?? userKey else { throw VaultCryptoError.invalidKey }
                if let itemKey = cipher.key { key = try VaultKey(EncString(itemKey).decrypt(key)) }
                guard let item = try item(cipher, key: key, folders: folders, organizations: organizationNames) else { continue }
                items.append(item)
            } catch { failures += 1 }
        }
        return Opened(items: items, failures: failures)
    }
    /// Unknown item types are skipped rather than counted as failures.
    static func item(_ cipher: VaultSync.Cipher, key: VaultKey, folders: [String: String], organizations: [String: String]) throws -> VaultItem? {
        guard let kind = VaultItem.Kind(rawValue: cipher.type) else { return nil }
        func text(_ value: String?) throws -> String { try value.map { try EncString($0).decryptString(key) } ?? "" }
        var item = VaultItem(id: cipher.id, kind: kind, name: try text(cipher.name))
        item.notes = try text(cipher.notes)
        item.favorite = cipher.favorite ?? false
        item.reprompt = (cipher.reprompt ?? 0) != 0
        item.folder = cipher.folderId.flatMap { folders[$0] }
        item.organization = cipher.organizationId.flatMap { organizations[$0] }
        func add(_ name: String, _ value: String?, hidden: Bool = false) throws {
            let plain = try text(value)
            if !plain.isEmpty { item.fields.append(.init(name: name, value: plain, hidden: hidden)) }
        }
        if let login = cipher.login {
            item.username = try text(login.username); item.password = try text(login.password); item.totp = try text(login.totp)
            item.uris = try (login.uris ?? []).map { try text($0.uri) }.filter { !$0.isEmpty }
        }
        if let card = cipher.card {
            try add("Cardholder", card.cardholderName); try add("Brand", card.brand); try add("Number", card.number, hidden: true)
            let month = try text(card.expMonth), year = try text(card.expYear)
            if !month.isEmpty || !year.isEmpty { item.fields.append(.init(name: "Expires", value: [month, year].filter { !$0.isEmpty }.joined(separator: " / "))) }
            try add("Security code", card.code, hidden: true)
        }
        if let identity = cipher.identity {
            let name = try [identity.title, identity.firstName, identity.middleName, identity.lastName].map(text).filter { !$0.isEmpty }.joined(separator: " ")
            if !name.isEmpty { item.fields.append(.init(name: "Name", value: name)) }
            try add("Company", identity.company); try add("Email", identity.email); try add("Phone", identity.phone); try add("Username", identity.username)
            let address = try [identity.address1, identity.address2, identity.address3].map(text).filter { !$0.isEmpty }
            let locality = try [identity.city, identity.state, identity.postalCode].map(text).filter { !$0.isEmpty }.joined(separator: " ")
            let lines = address + [locality, try text(identity.country)].filter { !$0.isEmpty }
            if !lines.isEmpty { item.fields.append(.init(name: "Address", value: lines.joined(separator: "\n"))) }
            try add("Social Security number", identity.ssn, hidden: true); try add("Passport number", identity.passportNumber, hidden: true); try add("License number", identity.licenseNumber, hidden: true)
        }
        if let ssh = cipher.sshKey {
            try add("Public key", ssh.publicKey); try add("Fingerprint", ssh.keyFingerprint); try add("Private key", ssh.privateKey, hidden: true)
        }
        for field in cipher.fields ?? [] where field.type != 3 {    // Linked fields have no value of their own.
            let name = try text(field.name), value = try text(field.value)
            item.fields.append(.init(name: name.isEmpty ? "Field" : name, value: field.type == 2 ? (value == "true" ? "Yes" : "No") : value, hidden: field.type == 1))
        }
        return item
    }
}

struct VaultAccount: Codable, Equatable {
    var server: VaultServer
    var email: String
    /// Set when signed in with a personal API key; the secret is kept in the Keychain.
    var apiClientID: String?
}

/// The encrypted vault kept on disk so it can be unlocked offline. It contains no key that opens it without the master password.
struct VaultCache: Codable {
    var version = 1
    var account: VaultAccount
    var kdf: VaultKDF
    var salt: String
    var sync: Data
    var syncedAt: Date
}

protocol VaultSecrets: Sendable {
    func read(_ name: String) -> String?
    func write(_ value: String?, for name: String)
}
/// Generic-password Keychain items, available only on this Mac while it's unlocked.
struct KeychainSecrets: VaultSecrets {
    let service: String
    func query(_ name: String) -> [CFString: Any] { [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: name] }
    func read(_ name: String) -> String? {
        var query = query(name); query[kSecReturnData] = true; query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func write(_ value: String?, for name: String) {
        SecItemDelete(query(name) as CFDictionary)
        guard let value else { return }
        var item = query(name)
        item[kSecValueData] = Data(value.utf8)
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

enum VaultError: LocalizedError {
    case noMasterPassword, signedOut
    var errorDescription: String? {
        switch self {
        case .noMasterPassword: return "This account doesn’t unlock with a master password, which Snippet requires."
        case .signedOut: return "Sign in to your vault first."
        }
    }
}

/// Signs in to a Bitwarden-compatible server, keeps the encrypted vault cached, and holds decrypted items only while unlocked.
final class VaultStore: ObservableObject {
    enum State: Equatable { case signedOut, locked, unlocked }
    enum Step: Equatable { case credentials, code([VaultTwoFactorProvider]), newDevice }
    @Published private(set) var state: State
    @Published private(set) var items: [VaultItem] = []
    @Published private(set) var busy = false
    @Published private(set) var step = Step.credentials
    @Published var message = ""
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "vaultEnabled"); if !enabled { lock() } } }
    @Published var lockMinutes: Int { didSet { defaults.set(lockMinutes, forKey: "vaultLockMinutes"); touch() } }
    @Published var clipboardSeconds: Int { didSet { defaults.set(clipboardSeconds, forKey: "vaultClipboardSeconds") } }
    private(set) var cache: VaultCache?
    private var userKey: VaultKey?
    private var accessToken: (value: String, expires: Date)?
    private var lockTimer: Timer?
    private var pending: Pending?
    private var refreshing = false
    /// Keychain calls can block on a system prompt (for example after an ad-hoc rebuild), so they never run on the main thread.
    private let secretQueue = DispatchQueue(label: "Snippet.vault.secrets", qos: .userInitiated)
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private struct Pending { var api: VaultAPI; var account: VaultAccount; var kdf: VaultKDF; var salt: String; var masterKey: Data; var hash: String; var apiSecret: String?; var sentRemembered: Bool }
    let defaults: UserDefaults
    let cacheURL: URL
    let secrets: VaultSecrets
    let transport: VaultAPI.Transport
    var account: VaultAccount? { cache?.account }
    var lastServer: VaultServer { (defaults.data(forKey: "vaultServer").flatMap { try? JSONDecoder().decode(VaultServer.self, from: $0) }) ?? VaultServer(kind: .bitwardenUS) }
    var lastEmail: String { defaults.string(forKey: "vaultEmail") ?? "" }
    var deviceID: String {
        if let id = defaults.string(forKey: "vaultDeviceID") { return id }
        let id = UUID().uuidString.lowercased(); defaults.set(id, forKey: "vaultDeviceID"); return id
    }

    init(defaults: UserDefaults = AppEnvironment.defaults, cacheURL: URL? = nil, secrets: VaultSecrets = KeychainSecrets(service: AppEnvironment.current.bundleIdentifier + ".vault"), transport: @escaping VaultAPI.Transport = VaultAPI.ephemeral, observeSystem: Bool = true) {
        self.defaults = defaults; self.secrets = secrets; self.transport = transport
        self.cacheURL = cacheURL ?? AppEnvironment.current.dataURL("vault-cache.json")
        enabled = defaults.bool(forKey: "vaultEnabled")
        lockMinutes = defaults.object(forKey: "vaultLockMinutes") as? Int ?? 15
        clipboardSeconds = defaults.object(forKey: "vaultClipboardSeconds") as? Int ?? 30
        state = .signedOut
        do {
            if FileManager.default.fileExists(atPath: self.cacheURL.path) {
                cache = try JSONDecoder().decode(VaultCache.self, from: Data(contentsOf: self.cacheURL))
                state = .locked
            }
        } catch { message = "Couldn’t read the saved vault. Sign out and sign in again. " + error.localizedDescription }
        guard observeSystem else { return }
        // Sleep, the screen locking and switching users all lock the vault.
        let workspace = NSWorkspace.shared.notificationCenter, distributed = DistributedNotificationCenter.default()
        for (center, name) in [(workspace, NSWorkspace.willSleepNotification), (workspace, NSWorkspace.sessionDidResignActiveNotification), (distributed, Notification.Name("com.apple.screenIsLocked"))] {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.lock() }))
        }
    }
    deinit { for (center, observer) in observers { center.removeObserver(observer) } }

    // MARK: Sign-in

    @MainActor func signIn(server: VaultServer, email: String, password: String, apiKey: (id: String, secret: String)? = nil) async {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !busy, !email.isEmpty, !password.isEmpty else { return }
        busy = true; message = ""; step = .credentials
        defer { busy = false }
        do {
            defaults.set(try JSONEncoder().encode(server), forKey: "vaultServer"); defaults.set(email, forKey: "vaultEmail")
            let api = VaultAPI(server: server, deviceID: deviceID, transport: transport)
            let kdf = try await api.prelogin(email: email)
            let settings = try kdf.settings(), salt = kdf.salt ?? email
            let masterKey = try await Task.detached(priority: .userInitiated) { try VaultCrypto.masterKey(password: password, salt: salt, kdf: settings) }.value
            let apiID = apiKey?.id.trimmingCharacters(in: .whitespaces)
            pending = Pending(api: api, account: VaultAccount(server: server, email: email, apiClientID: apiID), kdf: settings, salt: salt, masterKey: masterKey,
                              hash: VaultCrypto.serverHash(masterKey: masterKey, password: password), apiSecret: apiKey?.secret.trimmingCharacters(in: .whitespaces), sentRemembered: false)
            try await finishSignIn()
        } catch { fail(error) }
    }
    /// Continues a sign-in that asked for a two-step or new-device code.
    @MainActor func submit(code: String, provider: VaultTwoFactorProvider? = nil, remember: Bool = false) async {
        let code = code.filter { !$0.isWhitespace }
        guard !busy, pending != nil, !code.isEmpty else { return }
        busy = true; message = ""
        defer { busy = false }
        do {
            if case .newDevice = step { try await finishSignIn(newDeviceCode: code) }
            else if let provider { try await finishSignIn(secondFactor: VaultSecondFactor(provider: provider, code: code, remember: remember)) }
        } catch { fail(error) }
    }
    @MainActor func sendEmailCode() async {
        guard let pending, !busy else { return }
        busy = true; defer { busy = false }
        do { try await pending.api.sendEmailCode(email: pending.account.email, hash: pending.hash); message = "Code sent. Check your email." }
        catch { message = error.localizedDescription }
    }
    func cancelSignIn() { pending = nil; step = .credentials; message = "" }
    @MainActor private func finishSignIn(secondFactor: VaultSecondFactor? = nil, newDeviceCode: String? = nil) async throws {
        guard var pending else { return }
        let grant: VaultGrant = pending.account.apiClientID.map { .apiKey(clientID: $0, secret: pending.apiSecret ?? "") } ?? .password(email: pending.account.email, hash: pending.hash)
        let remembered = secondFactor == nil ? await secret("twoFactorRemember") : nil
        pending.sentRemembered = remembered != nil; self.pending = pending
        let token: VaultToken
        do { token = try await pending.api.token(grant, secondFactor: secondFactor, newDeviceCode: newDeviceCode, rememberedDevice: remembered) }
        catch VaultAPIError.twoFactorRequired(let providers) {
            if pending.sentRemembered { setSecret(nil, for: "twoFactorRemember") }
            step = .code(providers)
            if providers.allSatisfy({ !$0.supported }) {
                message = "Snippet supports authenticator, email and YubiKey OTP codes. Sign in with your personal API key instead."
            }
            return
        } catch VaultAPIError.newDeviceCode { step = .newDevice; return }
        let data = try await pending.api.sync(accessToken: token.accessToken)
        let sync = try VaultAPI.decoder.decode(VaultSync.self, from: data)
        guard let protected = sync.profile.key ?? token.key else { throw VaultError.noMasterPassword }
        let masterKey = pending.masterKey
        let (key, opened) = try await Task.detached(priority: .userInitiated) { () -> (VaultKey, VaultDecoder.Opened) in
            let key = try VaultCrypto.userKey(protected, masterKey: masterKey)
            return (key, try VaultDecoder.open(sync, userKey: key))
        }.value
        let cache = VaultCache(account: pending.account, kdf: pending.kdf, salt: pending.salt, sync: data, syncedAt: Date())
        try WorkspaceStore.write(cache, to: cacheURL)
        setSecret(token.refreshToken, for: "refreshToken")
        setSecret(pending.apiSecret, for: "apiKeySecret")
        if let remember = token.twoFactorToken { setSecret(remember, for: "twoFactorRemember") }
        self.cache = cache; self.pending = nil; step = .credentials
        accessToken = (token.accessToken, Date().addingTimeInterval(token.expiresIn))
        open(opened, key: key)
    }

    // MARK: Lock state

    /// Opens the saved vault offline. Call `refresh()` afterwards to sync.
    @MainActor func unlock(password: String) async {
        guard let cache, !busy, !password.isEmpty else { return }
        busy = true; message = ""
        defer { busy = false }
        do {
            let (key, opened) = try await Task.detached(priority: .userInitiated) { () -> (VaultKey, VaultDecoder.Opened) in
                let sync = try VaultAPI.decoder.decode(VaultSync.self, from: cache.sync)
                guard let protected = sync.profile.key else { throw VaultError.noMasterPassword }
                let key = try VaultCrypto.userKey(protected, masterKey: VaultCrypto.masterKey(password: password, salt: cache.salt, kdf: cache.kdf))
                return (key, try VaultDecoder.open(sync, userKey: key))
            }.value
            open(opened, key: key)
        } catch { fail(error) }
    }
    /// Confirms the master password for items that ask for it again.
    @MainActor func verify(password: String) async -> Bool {
        guard let cache else { return false }
        return await Task.detached(priority: .userInitiated) {
            guard let sync = try? VaultAPI.decoder.decode(VaultSync.self, from: cache.sync), let protected = sync.profile.key,
                  let master = try? VaultCrypto.masterKey(password: password, salt: cache.salt, kdf: cache.kdf) else { return false }
            return (try? VaultCrypto.userKey(protected, masterKey: master)) != nil
        }.value
    }
    func lock() {
        lockTimer?.invalidate(); lockTimer = nil
        userKey = nil; accessToken = nil; items = []
        if state == .unlocked { state = .locked }
    }
    func signOut() {
        lock(); cancelSignIn()
        try? FileManager.default.removeItem(at: cacheURL)
        for name in ["refreshToken", "apiKeySecret", "twoFactorRemember"] { setSecret(nil, for: name) }
        cache = nil; state = .signedOut; message = ""
    }
    /// Restarts the inactivity timer. Every use of the vault counts as activity.
    func touch() {
        lockTimer?.invalidate(); lockTimer = nil
        guard state == .unlocked else { return }
        let timer = Timer(timeInterval: TimeInterval(max(lockMinutes, 1) * 60), repeats: false) { [weak self] _ in self?.lock() }
        RunLoop.main.add(timer, forMode: .common)
        lockTimer = timer
    }
    private func open(_ opened: VaultDecoder.Opened, key: VaultKey) {
        userKey = key
        items = opened.items
        state = .unlocked
        message = opened.failures == 0 ? "" : "\(opened.failures) item\(opened.failures == 1 ? "" : "s") couldn’t be decrypted and \(opened.failures == 1 ? "is" : "are") hidden."
        touch()
    }
    private func fail(_ error: Error) {
        if case VaultAPIError.unauthorized = error, pending == nil { message = "Your session has expired. Your saved vault is still available; sign out and sign in again to sync."; return }
        message = error.localizedDescription
    }

    // MARK: Sync

    var needsRefresh: Bool { state == .unlocked && !busy && !refreshing && (cache.map { Date().timeIntervalSince($0.syncedAt) > 300 } ?? false) }
    /// Downloads the latest vault. A changed master password, KDF or account key locks the vault so it reopens with the current password.
    @MainActor func refresh() async {
        guard let cache, let userKey, state == .unlocked, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let api = VaultAPI(server: cache.account.server, deviceID: deviceID, transport: transport)
            let token = try await validToken(api, account: cache.account)
            let data = try await api.sync(accessToken: token)
            let sync = try VaultAPI.decoder.decode(VaultSync.self, from: data)
            let old = try VaultAPI.decoder.decode(VaultSync.self, from: cache.sync)
            var next = cache
            if let prelogin = try? await api.prelogin(email: cache.account.email), let kdf = try? prelogin.settings() { next.kdf = kdf; next.salt = prelogin.salt ?? cache.account.email }
            next.sync = data; next.syncedAt = Date()
            guard sync.profile.key == old.profile.key, next.kdf == cache.kdf, next.salt == cache.salt else {
                try WorkspaceStore.write(next, to: cacheURL); self.cache = next
                lock(); message = "Your master password or encryption settings changed. Unlock with your current master password."
                return
            }
            let opened = try await Task.detached(priority: .userInitiated) { try VaultDecoder.open(sync, userKey: userKey) }.value
            try WorkspaceStore.write(next, to: cacheURL); self.cache = next
            guard state == .unlocked else { return }
            open(opened, key: userKey)
        } catch { fail(error) }
    }
    @MainActor private func validToken(_ api: VaultAPI, account: VaultAccount) async throws -> String {
        if let accessToken, accessToken.expires > Date().addingTimeInterval(60) { return accessToken.value }
        let token: VaultToken
        if let id = account.apiClientID {
            guard let secret = await secret("apiKeySecret") else { throw VaultAPIError.unauthorized }
            token = try await api.token(.apiKey(clientID: id, secret: secret))
        } else {
            guard let refresh = await secret("refreshToken") else { throw VaultAPIError.unauthorized }
            token = try await api.token(.refresh(refresh))
            if let next = token.refreshToken { setSecret(next, for: "refreshToken") }
        }
        accessToken = (token.accessToken, Date().addingTimeInterval(token.expiresIn))
        return token.accessToken
    }

    // MARK: Secrets

    /// Reads run after any queued writes.
    private func secret(_ name: String) async -> String? {
        await withCheckedContinuation { continuation in secretQueue.async { [secrets] in continuation.resume(returning: secrets.read(name)) } }
    }
    private func setSecret(_ value: String?, for name: String) { secretQueue.async { [secrets] in secrets.write(value, for: name) } }
    /// Waits for queued Keychain writes.
    func secretsSettled() async { await withCheckedContinuation { continuation in secretQueue.async { continuation.resume() } } }

    // MARK: Search

    func search(_ query: String, favorites: Bool = false) -> [VaultItem] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return items.filter { item in (!favorites || item.favorite) && words.allSatisfy { item.searchText.localizedStandardContains($0) } }
            .sorted { $0.favorite != $1.favorite ? $0.favorite : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

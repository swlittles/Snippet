import Foundation

/// A Bitwarden-compatible server: Bitwarden's US or EU cloud, or a self-hosted Bitwarden or Vaultwarden instance.
struct VaultServer: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case bitwardenUS, bitwardenEU, selfHosted
        var id: String { rawValue }
        var title: String {
            switch self { case .bitwardenUS: return "Bitwarden.com"; case .bitwardenEU: return "Bitwarden.eu"; case .selfHosted: return "Self-hosted" }
        }
    }
    var kind: Kind
    var url = ""
    /// Self-hosted servers serve both APIs under one address; the cloud uses separate hosts.
    func endpoints() throws -> (api: URL, identity: URL) {
        switch kind {
        case .bitwardenUS: return (URL(string: "https://api.bitwarden.com")!, URL(string: "https://identity.bitwarden.com")!)
        case .bitwardenEU: return (URL(string: "https://api.bitwarden.eu")!, URL(string: "https://identity.bitwarden.eu")!)
        case .selfHosted:
            let base = try Self.normalized(url)
            return (base.appendingPathComponent("api"), base.appendingPathComponent("identity"))
        }
    }
    var displayName: String { kind == .selfHosted ? ((try? Self.normalized(url))?.host ?? url) : kind.title }
    /// Requires HTTPS, except for a server on this Mac.
    static func normalized(_ string: String) throws -> URL {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let components = URLComponents(string: text), let host = components.host, !host.isEmpty,
              components.query == nil, components.fragment == nil, components.user == nil, let url = components.url else { throw VaultAPIError.invalidServer }
        let local = ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
        guard components.scheme == "https" || (components.scheme == "http" && local) else { throw VaultAPIError.insecureServer }
        return url
    }
}

enum VaultTwoFactorProvider: Int, Codable, CaseIterable, Identifiable {
    case authenticator = 0, email = 1, duo = 2, yubiKey = 3, u2f = 4, remember = 5, organizationDuo = 6, webAuthn = 7
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .authenticator: return "Authenticator app"
        case .email: return "Email"
        case .duo, .organizationDuo: return "Duo"
        case .yubiKey: return "YubiKey OTP"
        case .u2f, .webAuthn: return "Security key"
        case .remember: return "Remembered device"
        }
    }
    /// Providers that take a typed code. Duo and security keys need a browser.
    var supported: Bool { self == .authenticator || self == .email || self == .yubiKey }
}

enum VaultAPIError: LocalizedError, Equatable {
    case invalidServer, insecureServer, invalidResponse, unauthorized
    case network(String), server(String)
    case twoFactorRequired([VaultTwoFactorProvider])
    case newDeviceCode
    var errorDescription: String? {
        switch self {
        case .invalidServer: return "Enter your server’s address, for example https://vault.example.com."
        case .insecureServer: return "The server address must use HTTPS."
        case .invalidResponse: return "The server sent an unexpected response. Check the server address."
        case .unauthorized: return "Your session has expired. Sign in again."
        case .network(let message): return "Couldn’t reach the server: " + message
        case .server(let message): return message
        case .twoFactorRequired: return "Enter your two-step login code."
        case .newDeviceCode: return "Enter the verification code emailed to you."
        }
    }
}

struct VaultToken: Decodable {
    var accessToken: String
    var expiresIn: Double
    var refreshToken: String?
    var key: String?
    var privateKey: String?
    var twoFactorToken: String?
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", expiresIn = "expires_in", refreshToken = "refresh_token", key, privateKey, twoFactorToken
    }
}

struct VaultPrelogin: Decodable {
    var kdf: Int
    var kdfIterations: Int
    var kdfMemory: Int?
    var kdfParallelism: Int?
    var salt: String?
    func settings() throws -> VaultKDF {
        guard let kind = VaultKDF.Kind(rawValue: kdf) else { throw VaultCryptoError.unsupportedKDF }
        return VaultKDF(kind: kind, iterations: kdfIterations, memory: kdfMemory, parallelism: kdfParallelism)
    }
}

enum VaultGrant {
    case password(email: String, hash: String)
    case apiKey(clientID: String, secret: String)
    case refresh(String)
}
struct VaultSecondFactor {
    var provider: VaultTwoFactorProvider
    var code: String
    var remember = false
}

/// The Bitwarden client API. Only derived hashes, tokens and ciphertext cross the network.
struct VaultAPI {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    static let ephemeral: Transport = {
        // No cookies, credential storage or on-disk response cache.
        let session = URLSession(configuration: .ephemeral)
        return { try await session.data(for: $0) }
    }()
    static let clientID = "desktop"
    static let deviceType = "7"     // macOS desktop
    let server: VaultServer
    let deviceID: String
    var transport: Transport = VaultAPI.ephemeral
    static let decoder: JSONDecoder = {
        // Bitwarden sends camelCase and Vaultwarden has historically sent PascalCase; accept either.
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { keys in CamelKey(keys.last!.stringValue) }
        return decoder
    }()
    struct CamelKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string.prefix(1).lowercased() + string.dropFirst() }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { nil }
    }

    func prelogin(email: String) async throws -> VaultPrelogin {
        let identity = try server.endpoints().identity
        var request = URLRequest(url: identity.appendingPathComponent("accounts/prelogin"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
        return try Self.decoder.decode(VaultPrelogin.self, from: await send(request))
    }
    func token(_ grant: VaultGrant, secondFactor: VaultSecondFactor? = nil, newDeviceCode: String? = nil, rememberedDevice: String? = nil) async throws -> VaultToken {
        var form = ["deviceType": Self.deviceType, "deviceIdentifier": deviceID, "deviceName": "Snippet"]
        var email: String?
        switch grant {
        case .password(let address, let hash):
            email = address
            form.merge(["grant_type": "password", "username": address, "password": hash, "scope": "api offline_access", "client_id": Self.clientID]) { $1 }
        case .apiKey(let clientID, let secret):
            form.merge(["grant_type": "client_credentials", "client_id": clientID, "client_secret": secret, "scope": "api"]) { $1 }
        case .refresh(let token):
            form = ["grant_type": "refresh_token", "client_id": Self.clientID, "refresh_token": token]
        }
        if let secondFactor {
            form.merge(["twoFactorProvider": String(secondFactor.provider.rawValue), "twoFactorToken": secondFactor.code, "twoFactorRemember": secondFactor.remember ? "1" : "0"]) { $1 }
        } else if let rememberedDevice {
            form.merge(["twoFactorProvider": String(VaultTwoFactorProvider.remember.rawValue), "twoFactorToken": rememberedDevice, "twoFactorRemember": "0"]) { $1 }
        }
        if let newDeviceCode { form["newdeviceotp"] = newDeviceCode }
        var request = URLRequest(url: try server.endpoints().identity.appendingPathComponent("connect/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if let email { request.setValue(Data(email.utf8).base64URLEncodedString(), forHTTPHeaderField: "Auth-Email") }
        request.httpBody = Data(Self.formEncoded(form).utf8)
        return try Self.decoder.decode(VaultToken.self, from: await send(request))
    }
    /// The full encrypted vault: profile keys, folders and items.
    func sync(accessToken: String) async throws -> Data {
        var components = URLComponents(url: try server.endpoints().api.appendingPathComponent("sync"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "excludeDomains", value: "true")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        return try await send(request)
    }
    /// Asks the server to email a two-step login code.
    func sendEmailCode(email: String, hash: String) async throws {
        var request = URLRequest(url: try server.endpoints().api.appendingPathComponent("two-factor/send-email-login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "masterPasswordHash": hash, "deviceIdentifier": deviceID])
        _ = try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.deviceType, forHTTPHeaderField: "Device-Type")
        let data: Data, response: URLResponse
        do { (data, response) = try await transport(request) }
        catch { throw VaultAPIError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw VaultAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw Self.error(status: http.statusCode, body: data) }
        return data
    }
    static func error(status: Int, body: Data) -> VaultAPIError {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        func value(_ key: String, in object: [String: Any] = json) -> Any? { object.first { $0.key.lowercased() == key.lowercased() }?.value }
        let providerKeys: [String] = (value("TwoFactorProviders2") as? [String: Any]).map { Array($0.keys) }
            ?? (value("TwoFactorProviders") as? [Any])?.map { "\($0)" } ?? []
        let providers = providerKeys.compactMap { Int($0).flatMap(VaultTwoFactorProvider.init(rawValue:)) }.sorted { $0.rawValue < $1.rawValue }
        if !providers.isEmpty { return .twoFactorRequired(providers) }
        let model = value("ErrorModel") as? [String: Any]
        let message = (model.flatMap { value("Message", in: $0) } as? String) ?? (value("error_description") as? String) ?? (value("message") as? String)
        if message?.lowercased().contains("new device verification") == true { return .newDeviceCode }
        if status == 401 { return .unauthorized }
        if let message, !message.isEmpty { return .server(message) }
        return status == 404 ? .invalidResponse : .server("The server returned an error (\(status)).")
    }
    static func formEncoded(_ form: [String: String]) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return form.sorted { $0.key < $1.key }.map { key, value in
            key + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&")
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

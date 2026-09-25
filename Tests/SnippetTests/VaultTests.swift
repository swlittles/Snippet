import Foundation
import Security

private func hex(_ bytes: some Sequence<UInt8>) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

/// A minimal Bitwarden-compatible server built from the client's own primitives, with synthetic data only.
private final class FakeVaultServer {
    let email = "ada@example.com", password = "correct horse battery"
    let kdf = VaultKDF(kind: .pbkdf2, iterations: 5_000)
    let userKey = VaultKey.random(), organizationKey = VaultKey.random(), itemKey = VaultKey.random()
    var protectedKey: String
    let privateKey: SecKey, protectedPrivateKey: String, protectedOrganizationKey: String
    let hash: String
    let totpSecret = "JBSWY3DPEHPK3PXP"
    var extraItems: [[String: Any]] = []
    var requireNewDevice = false
    var requests: [String] = []
    var refreshToken = "refresh-1"
    init() throws {
        let masterKey = try VaultCrypto.masterKey(password: password, salt: email, kdf: kdf)
        hash = VaultCrypto.serverHash(masterKey: masterKey, password: password)
        protectedKey = try EncString.encrypt(userKey.data, key: VaultCrypto.stretch(masterKey)).string
        privateKey = SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, nil)!
        let pkcs1 = SecKeyCopyExternalRepresentation(privateKey, nil)! as Data
        protectedPrivateKey = try EncString.encrypt(DER.pkcs8(fromPKCS1: pkcs1), key: userKey).string
        let wrapped = SecKeyCreateEncryptedData(SecKeyCopyPublicKey(privateKey)!, .rsaEncryptionOAEPSHA1, organizationKey.data as CFData, nil)! as Data
        protectedOrganizationKey = EncString(kind: .rsaOaepSha1, data: wrapped).string
    }
    func seal(_ text: String, _ key: VaultKey? = nil) -> String { try! EncString.encrypt(Data(text.utf8), key: key ?? userKey).string }
    var sync: [String: Any] {
        var tampered = try! EncString(seal("Broken"))
        tampered = EncString(kind: tampered.kind, iv: tampered.iv, data: tampered.data, mac: Data(repeating: 0, count: 32))
        let ciphers: [[String: Any]] = [
            ["id": "11111111-1111-1111-1111-111111111111", "type": 1, "folderId": "f1", "favorite": true, "name": seal("Example Mail"), "notes": NSNull(),
             "login": ["username": seal("ada"), "password": seal("hunter2"), "totp": seal("otpauth://totp/Example:ada?secret=\(totpSecret)&period=30"),
                       "uris": [["uri": seal("https://mail.example.org/login"), "match": NSNull()]], "fido2Credentials": []],
             "fields": [["name": seal("PIN"), "value": seal("4321"), "type": 1], ["name": seal("Linked"), "value": NSNull(), "type": 3]], "passwordHistory": []],
            ["id": "22222222-2222-2222-2222-222222222222", "type": 1, "name": seal("Keyed item", itemKey), "key": try! EncString.encrypt(itemKey.data, key: userKey).string,
             "login": ["username": seal("grace", itemKey), "password": seal("s3cret", itemKey)]],
            ["id": "33333333-3333-3333-3333-333333333333", "type": 3, "organizationId": "o1", "name": seal("Team card", organizationKey),
             "card": ["cardholderName": seal("Ada Lovelace", organizationKey), "brand": seal("Visa", organizationKey), "number": seal("4111111111111111", organizationKey),
                      "expMonth": seal("12", organizationKey), "expYear": seal("2030", organizationKey), "code": seal("123", organizationKey)]],
            ["id": "44444444-4444-4444-4444-444444444444", "type": 2, "reprompt": 1, "name": seal("Recovery codes"), "notes": seal("alpha beta"), "secureNote": ["type": 0]],
            ["id": "55555555-5555-5555-5555-555555555555", "type": 1, "name": seal("Trashed"), "deletedDate": "2026-01-01T00:00:00Z"],
            ["id": "66666666-6666-6666-6666-666666666666", "type": 1, "name": tampered.string],
            ["id": "77777777-7777-7777-7777-777777777777", "type": 99, "name": seal("From the future")],
        ] + extraItems
        return ["object": "sync", "profile": ["id": "u1", "email": email, "key": protectedKey, "privateKey": protectedPrivateKey,
                                              "organizations": [["id": "o1", "name": "Analytical Engines", "key": protectedOrganizationKey]]],
                "folders": [["id": "f1", "name": seal("Work")]], "ciphers": ciphers, "collections": [], "policies": [], "sends": []]
    }
    func respond(_ request: URLRequest) throws -> (Data, URLResponse) {
        let path = request.url!.path
        requests.append(path)
        func reply(_ status: Int, _ object: Any) -> (Data, URLResponse) {
            (try! JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        switch path {
        case "/identity/accounts/prelogin": return reply(200, ["kdf": 0, "kdfIterations": kdf.iterations, "kdfMemory": NSNull(), "kdfParallelism": NSNull(), "salt": NSNull()])
        case "/identity/connect/token":
            let form = Dictionary(uniqueKeysWithValues: String(data: request.httpBody!, encoding: .utf8)!.split(separator: "&").map { pair -> (String, String) in
                let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding! }
                return (parts[0], parts.count > 1 ? parts[1] : "")
            })
            let token: [String: Any] = ["access_token": "access-" + UUID().uuidString, "expires_in": 3600, "token_type": "Bearer", "refresh_token": refreshToken, "Key": protectedKey, "PrivateKey": protectedPrivateKey]
            if form["grant_type"] == "refresh_token" {
                guard form["refresh_token"] == refreshToken else { return reply(400, ["error": "invalid_grant"]) }
                refreshToken = "refresh-" + UUID().uuidString
                return reply(200, token.merging(["refresh_token": refreshToken]) { $1 })
            }
            guard form["grant_type"] == "password", form["password"] == hash, form["username"] == email, form["deviceIdentifier"]?.isEmpty == false,
                  request.value(forHTTPHeaderField: "Auth-Email") == Data(email.utf8).base64URLEncodedString() else {
                return reply(400, ["error": "invalid_grant", "error_description": "invalid_username_or_password", "ErrorModel": ["Message": "Username or password is incorrect. Try again", "Object": "error"]])
            }
            if requireNewDevice {
                guard form["newdeviceotp"] == "998877" else { return reply(400, ["error": "invalid_grant", "error_description": "New device verification required."]) }
                return reply(200, token)
            }
            if form["twoFactorProvider"] == "5" && form["twoFactorToken"] == "remembered" { return reply(200, token) }
            guard form["twoFactorProvider"] == "0", form["twoFactorToken"] == "123456" else {
                return reply(400, ["error": "invalid_grant", "error_description": "Two factor required.", "TwoFactorProviders": ["0", "7"], "TwoFactorProviders2": ["0": NSNull(), "7": ["Challenge": "…"]]])
            }
            return reply(200, token.merging(["TwoFactorToken": form["twoFactorRemember"] == "1" ? "remembered" : NSNull()]) { $1 })
        case "/api/sync":
            guard request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer access-") == true else { return reply(401, ["message": "Unauthorized"]) }
            return reply(200, sync)
        default: return reply(404, [:])
        }
    }
}

private final class MemorySecrets: VaultSecrets, @unchecked Sendable {
    var values: [String: String] = [:]
    func read(_ name: String) -> String? { values[name] }
    func write(_ value: String?, for name: String) { values[name] = value }
}

extension StoreTests {
    func testVaultCrypto() throws {
        XCTAssertEqual(hex(Blake2b.hash(Array("abc".utf8))), "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923")
        // RFC 9106 §5.3
        let argon = Argon2.hash(password: Data(repeating: 1, count: 32), salt: Data(repeating: 2, count: 16), iterations: 3, memoryKiB: 32, parallelism: 4, length: 32,
                                secret: Data(repeating: 3, count: 8), associated: Data(repeating: 4, count: 12))
        XCTAssertEqual(hex(argon), "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659")
        XCTAssertEqual(hex(VaultCrypto.pbkdf2(Data("password".utf8), salt: Data("salt".utf8), iterations: 4096)), "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
        // Argon2id salts with the SHA-256 of the email, and takes memory in MiB.
        let argonKDF = VaultKDF(kind: .argon2id, iterations: 3, memory: 16, parallelism: 2)
        XCTAssertEqual(try VaultCrypto.masterKey(password: "pw", salt: "ada@example.com", kdf: argonKDF),
                       Argon2.hash(password: Data("pw".utf8), salt: VaultCrypto.sha256(Data("ada@example.com".utf8)), iterations: 3, memoryKiB: 16 * 1024, parallelism: 2, length: 32))
        do { _ = try VaultCrypto.masterKey(password: "pw", salt: "a", kdf: VaultKDF(kind: .pbkdf2, iterations: 10)); preconditionFailure("Accepted a weak KDF") } catch {}

        // RFC 6238 appendix B
        let seconds: [Double] = [59, 1111111109, 2000000000]
        XCTAssertEqual(seconds.map { TOTP(secret: Data("12345678901234567890".utf8), digits: 8).code(at: Date(timeIntervalSince1970: $0)) }, ["94287082", "07081804", "69279037"])
        XCTAssertEqual(TOTP(secret: Data("12345678901234567890123456789012".utf8), algorithm: .sha256, digits: 8).code(at: Date(timeIntervalSince1970: 59)), "46119246")
        XCTAssertEqual(TOTP(secret: Data(String(repeating: "1234567890", count: 7).prefix(64).utf8), algorithm: .sha512, digits: 8).code(at: Date(timeIntervalSince1970: 59)), "90693936")
        XCTAssertEqual(Base32.decode("JBSWY3DPEHPK3PXP"), Data("Hello!".utf8) + Data([0xde, 0xad, 0xbe, 0xef]))
        let uri = try TOTP("otpauth://totp/Example:ada?secret=jbsw%20y3dpehpk3pxp&algorithm=SHA256&digits=8&period=60")
        XCTAssertEqual(uri, TOTP(secret: Base32.decode("JBSWY3DPEHPK3PXP")!, algorithm: .sha256, digits: 8, period: 60))
        XCTAssertEqual(uri.remaining(at: Date(timeIntervalSince1970: 61)), 59)
        XCTAssertEqual(try TOTP(" jbsw y3dp ehpk 3pxp ").secret, Base32.decode("JBSWY3DPEHPK3PXP"))
        let steam = try TOTP("steam://JBSWY3DPEHPK3PXP").code()
        XCTAssertTrue(steam.count == 5 && steam.allSatisfy { "23456789BCDFGHJKMNPQRTVWXY".contains($0) })
        for invalid in ["", "otpauth://hotp/x?secret=JBSW", "otpauth://totp/x?secret=JBSW&digits=0", "not base32!"] {
            do { _ = try TOTP(invalid); preconditionFailure("Accepted TOTP " + invalid) } catch {}
        }

        let key = VaultKey.random(), other = VaultKey.random()
        let sealed = try EncString.encrypt(Data("secret ✓".utf8), key: key)
        XCTAssertEqual(try EncString(sealed.string), sealed)
        XCTAssertEqual(try EncString(sealed.string).decryptString(key), "secret ✓")
        do { _ = try sealed.decrypt(other); preconditionFailure("Opened with the wrong key") } catch { XCTAssertEqual(error as? VaultCryptoError, .wrongKey) }
        var bytes = [UInt8](sealed.data); bytes[0] ^= 1
        do { _ = try EncString(kind: sealed.kind, iv: sealed.iv, data: Data(bytes), mac: sealed.mac).decrypt(key); preconditionFailure("Accepted tampered data") } catch {}
        let legacyKey = VaultCrypto.random(32), iv = VaultCrypto.random(16)
        let legacy = EncString(kind: .aesCbc256, iv: iv, data: try VaultCrypto.aes(Data("old".utf8), key: legacyKey, iv: iv, operation: 0))
        XCTAssertEqual(try EncString(legacy.string).decryptString(VaultKey(legacyKey)), "old")
        do { _ = try legacy.decrypt(key); preconditionFailure("Opened unauthenticated data with an authenticated key") } catch {}
        for invalid in ["", "2.", "2.abc|def", "9.AAAA|AAAA", "x.AAAA", "2.@@@|AAAA|AAAA"] {
            do { _ = try EncString(invalid); preconditionFailure("Parsed " + invalid) } catch {}
        }
        do { _ = try EncString("7.AAAA"); preconditionFailure("Parsed a newer type") } catch { XCTAssertEqual(error as? VaultCryptoError, .unsupportedEncryption(7)) }

        XCTAssertEqual(try VaultServer.normalized(" vault.example.com/ ").absoluteString, "https://vault.example.com")
        XCTAssertEqual(try VaultServer(kind: .selfHosted, url: "https://example.com/bitwarden").endpoints().api.absoluteString, "https://example.com/bitwarden/api")
        XCTAssertEqual(try VaultServer.normalized("http://localhost:8080").absoluteString, "http://localhost:8080")
        do { _ = try VaultServer.normalized("http://vault.example.com"); preconditionFailure("Accepted plain HTTP") } catch { XCTAssertEqual(error as? VaultAPIError, .insecureServer) }
        do { _ = try VaultServer.normalized("https://vault.example.com/?x=1"); preconditionFailure("Accepted a query") } catch {}
        XCTAssertEqual(try VaultServer(kind: .bitwardenEU).endpoints().identity.absoluteString, "https://identity.bitwarden.eu")
        XCTAssertEqual(VaultAPI.formEncoded(["b": "a+b/c=é", "a": "x y@z"]), "a=x%20y%40z&b=a%2Bb%2Fc%3D%C3%A9")

        let pascal = Data(#"{"error":"invalid_grant","error_description":"Two factor required.","TwoFactorProviders":[0,1],"TwoFactorProviders2":{"1":{"Email":"a***@example.com"},"0":null}}"#.utf8)
        XCTAssertEqual(VaultAPI.error(status: 400, body: pascal), .twoFactorRequired([.authenticator, .email]))
        XCTAssertEqual(VaultAPI.error(status: 400, body: Data(#"{"message":"Nope","errorModel":{"message":"Bad email"}}"#.utf8)), .server("Bad email"))
        XCTAssertEqual(VaultAPI.error(status: 401, body: Data()), .unauthorized)
        XCTAssertEqual(VaultAPI.error(status: 400, body: Data(#"{"error_description":"New device verification required"}"#.utf8)), .newDeviceCode)
    }

    func testVaultSession() async throws {
        let name = "SnippetVaultTest-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try FakeVaultServer(), secrets = MemorySecrets()
        let cacheURL = directory.appendingPathComponent("vault-cache.json")
        let transport: VaultAPI.Transport = { try server.respond($0) }
        func makeVault() -> VaultStore { VaultStore(defaults: defaults, cacheURL: cacheURL, secrets: secrets, transport: transport, observeSystem: false) }
        let vault = makeVault()
        let address = VaultServer(kind: .selfHosted, url: "https://vault.example.test")
        XCTAssertEqual(vault.state, .signedOut)

        await vault.signIn(server: address, email: " Ada@Example.com ", password: "wrong")
        XCTAssertEqual(vault.state, .signedOut)
        XCTAssertEqual(vault.message, "Username or password is incorrect. Try again")

        await vault.signIn(server: address, email: "Ada@Example.com", password: server.password)
        XCTAssertEqual(vault.step, .code([.authenticator, .webAuthn]))
        XCTAssertEqual(vault.state, .signedOut)
        await vault.submit(code: "000000", provider: .authenticator)
        XCTAssertEqual(vault.state, .signedOut)
        await vault.submit(code: "123 456", provider: .authenticator, remember: true)
        await vault.secretsSettled()
        XCTAssertEqual(vault.state, .unlocked)
        XCTAssertEqual(vault.step, .credentials)
        XCTAssertEqual(secrets.values["twoFactorRemember"], "remembered")
        XCTAssertEqual(secrets.values["refreshToken"], server.refreshToken)
        XCTAssertEqual(vault.lastEmail, "ada@example.com")

        // Deleted and unknown items are skipped; the tampered one is reported.
        XCTAssertEqual(vault.items.count, 4)
        XCTAssertEqual(vault.message, "1 item couldn’t be decrypted and is hidden.")
        let login = vault.items.first { $0.name == "Example Mail" }!
        XCTAssertEqual([login.username, login.password, login.folder ?? ""], ["ada", "hunter2", "Work"])
        XCTAssertEqual(login.hosts, ["mail.example.org"])
        XCTAssertEqual(login.fields, [.init(name: "PIN", value: "4321", hidden: true)])
        XCTAssertEqual(login.primary, .init(name: "Password", value: "hunter2", hidden: true))
        XCTAssertEqual(login.codeField()?.value, TOTP(secret: Base32.decode(server.totpSecret)!).code())
        XCTAssertEqual(login.resultID.uuidString, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(vault.items.first { $0.name == "Keyed item" }?.password, "s3cret")
        let card = vault.items.first { $0.kind == .card }!
        XCTAssertEqual([card.organization ?? "", card.value("Number") ?? "", card.value("Expires") ?? "", card.subtitle], ["Analytical Engines", "4111111111111111", "12 / 2030", "Visa •••• 1111 · Analytical Engines"])
        XCTAssertEqual(card.primary?.value, "4111111111111111")
        let note = vault.items.first { $0.kind == .note }!
        XCTAssertTrue(note.reprompt && note.primary == .init(name: "Note", value: "alpha beta", hidden: true))

        XCTAssertEqual(vault.search("").first?.name, "Example Mail")        // favorites first
        XCTAssertEqual(vault.search("work ada").map(\.name), ["Example Mail"])
        XCTAssertEqual(vault.search("mail.example").map(\.name), ["Example Mail"])
        XCTAssertEqual(vault.search("analytical").map(\.name), ["Team card"])
        XCTAssertEqual(vault.search("", favorites: true).count, 1)

        // Only ciphertext is saved.
        let saved = try Data(contentsOf: cacheURL)
        for secret in ["hunter2", server.password, "4111111111111111", "alpha beta", server.refreshToken] { XCTAssertTrue(saved.range(of: Data(secret.utf8)) == nil) }
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        XCTAssertTrue(await vault.verify(password: server.password))
        XCTAssertFalse(await vault.verify(password: "wrong"))

        vault.lock()
        XCTAssertEqual(vault.state, .locked)
        XCTAssertTrue(vault.items.isEmpty)
        await vault.unlock(password: "wrong")
        XCTAssertEqual(vault.state, .locked)
        XCTAssertEqual(vault.message, "Incorrect master password.")

        // A relaunch unlocks offline from the saved vault.
        let relaunched = makeVault()
        XCTAssertEqual(relaunched.state, .locked)
        XCTAssertEqual(relaunched.account?.email, "ada@example.com")
        let requestsBefore = server.requests.count
        await relaunched.unlock(password: server.password)
        XCTAssertEqual(relaunched.state, .unlocked)
        XCTAssertEqual(relaunched.items.count, 4)
        XCTAssertEqual(server.requests.count, requestsBefore)

        // Refreshing uses the saved refresh token, rotates it and picks up changes.
        server.extraItems = [["id": "88888888-8888-8888-8888-888888888888", "type": 1, "name": server.seal("New login"), "login": ["username": server.seal("new")]]]
        let rotated = server.refreshToken
        await relaunched.refresh()
        await relaunched.secretsSettled()
        XCTAssertEqual(relaunched.items.count, 5)
        XCTAssertFalse(secrets.values["refreshToken"] == rotated)
        XCTAssertEqual(secrets.values["refreshToken"], server.refreshToken)
        XCTAssertEqual(makeVault().cache?.sync.isEmpty, false)

        // A changed master password locks the vault instead of mixing keys.
        server.protectedKey = try EncString.encrypt(server.userKey.data, key: VaultCrypto.stretch(VaultCrypto.random(32))).string
        await relaunched.refresh()
        XCTAssertEqual(relaunched.state, .locked)
        XCTAssertTrue(relaunched.message.contains("changed"))

        relaunched.signOut()
        await relaunched.secretsSettled()
        XCTAssertEqual(relaunched.state, .signedOut)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertTrue(secrets.values.isEmpty)

        // New-device verification, as Bitwarden's cloud requires for accounts without two-step login.
        let fresh = try FakeVaultServer(); fresh.requireNewDevice = true
        let second = VaultStore(defaults: defaults, cacheURL: cacheURL, secrets: MemorySecrets(), transport: { try fresh.respond($0) }, observeSystem: false)
        await second.signIn(server: address, email: fresh.email, password: fresh.password)
        XCTAssertEqual(second.step, .newDevice)
        await second.submit(code: "998877")
        XCTAssertEqual(second.state, .unlocked)
        second.signOut()
    }
}

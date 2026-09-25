import Foundation
import CommonCrypto
import CryptoKit
import Security

enum VaultCryptoError: LocalizedError, Equatable {
    case invalidEncString, unsupportedEncryption(Int), wrongKey, decryptionFailed, invalidKey, unsupportedKDF, invalidTOTP
    var errorDescription: String? {
        switch self {
        case .invalidEncString: return "The vault contains data in an unexpected format."
        case .unsupportedEncryption(let type): return "This vault uses an encryption type Snippet doesn’t support yet (\(type))."
        case .wrongKey: return "Incorrect master password."
        case .decryptionFailed: return "Couldn’t decrypt vault data."
        case .invalidKey: return "The vault key is invalid."
        case .unsupportedKDF: return "This account uses a key derivation setting Snippet doesn’t support."
        case .invalidTOTP: return "The saved authenticator key is invalid."
        }
    }
}

/// A 256-bit AES key paired with an HMAC-SHA256 key, or an AES key alone for legacy data.
struct VaultKey: Equatable {
    let encryption: Data
    let mac: Data?
    init(encryption: Data, mac: Data?) { self.encryption = encryption; self.mac = mac }
    /// Keys are stored as 64 bytes (encryption then MAC), or 32 for legacy encryption-only keys.
    init(_ data: Data) throws {
        switch data.count {
        case 64: encryption = data.prefix(32); mac = data.suffix(32)
        case 32: encryption = data; mac = nil
        default: throw VaultCryptoError.invalidKey
        }
    }
    var data: Data { encryption + (mac ?? Data()) }
    static func random() -> VaultKey { try! VaultKey(VaultCrypto.random(64)) }
}

/// Bitwarden's `type.iv|data|mac` ciphertext string.
struct EncString: Equatable {
    enum Kind: Int { case aesCbc256 = 0, aesCbc256HmacSha256 = 2, rsaOaepSha256 = 3, rsaOaepSha1 = 4 }
    let kind: Kind
    let iv: Data
    let data: Data
    let mac: Data?
    init(kind: Kind, iv: Data = Data(), data: Data, mac: Data? = nil) { self.kind = kind; self.iv = iv; self.data = data; self.mac = mac }
    init(_ string: String) throws {
        let header = string.split(separator: ".", maxSplits: 1)
        guard header.count == 2, let raw = Int(header[0]) else { throw VaultCryptoError.invalidEncString }
        guard let kind = Kind(rawValue: raw) else { throw VaultCryptoError.unsupportedEncryption(raw) }
        let parts = try header[1].split(separator: "|", omittingEmptySubsequences: false).map { part -> Data in
            guard let data = Data(base64Encoded: String(part)) else { throw VaultCryptoError.invalidEncString }
            return data
        }
        switch (kind, parts.count) {
        case (.aesCbc256, 2): self.init(kind: kind, iv: parts[0], data: parts[1])
        case (.aesCbc256HmacSha256, 3): self.init(kind: kind, iv: parts[0], data: parts[1], mac: parts[2])
        case (.rsaOaepSha256, 1), (.rsaOaepSha1, 1): self.init(kind: kind, data: parts[0])
        default: throw VaultCryptoError.invalidEncString
        }
    }
    var string: String {
        let parts = kind == .rsaOaepSha1 || kind == .rsaOaepSha256 ? [data] : [iv, data] + (mac.map { [$0] } ?? [])
        return "\(kind.rawValue)." + parts.map { $0.base64EncodedString() }.joined(separator: "|")
    }
    static func encrypt(_ plaintext: Data, key: VaultKey) throws -> EncString {
        guard let macKey = key.mac else { throw VaultCryptoError.invalidKey }
        let iv = VaultCrypto.random(16)
        let data = try VaultCrypto.aes(plaintext, key: key.encryption, iv: iv, operation: CCOperation(kCCEncrypt))
        return EncString(kind: .aesCbc256HmacSha256, iv: iv, data: data, mac: VaultCrypto.hmac(iv + data, key: macKey))
    }
    func decrypt(_ key: VaultKey) throws -> Data {
        switch kind {
        case .aesCbc256HmacSha256:
            guard let macKey = key.mac, let mac else { throw VaultCryptoError.wrongKey }
            guard VaultCrypto.constantTimeEqual(VaultCrypto.hmac(iv + data, key: macKey), mac) else { throw VaultCryptoError.wrongKey }
        case .aesCbc256:
            // Unauthenticated legacy data can only be opened with a legacy key.
            guard key.mac == nil else { throw VaultCryptoError.wrongKey }
        case .rsaOaepSha256, .rsaOaepSha1: throw VaultCryptoError.invalidKey
        }
        return try VaultCrypto.aes(data, key: key.encryption, iv: iv, operation: CCOperation(kCCDecrypt))
    }
    func decryptString(_ key: VaultKey) throws -> String {
        guard let text = String(data: try decrypt(key), encoding: .utf8) else { throw VaultCryptoError.decryptionFailed }
        return text
    }
    func decrypt(privateKey: SecKey) throws -> Data {
        let algorithm: SecKeyAlgorithm
        switch kind {
        case .rsaOaepSha1: algorithm = .rsaEncryptionOAEPSHA1
        case .rsaOaepSha256: algorithm = .rsaEncryptionOAEPSHA256
        default: throw VaultCryptoError.invalidKey
        }
        guard let plain = SecKeyCreateDecryptedData(privateKey, algorithm, data as CFData, nil) as Data? else { throw VaultCryptoError.decryptionFailed }
        return plain
    }
}

/// Account key derivation settings, as reported by the server's prelogin endpoint.
struct VaultKDF: Codable, Equatable {
    enum Kind: Int, Codable { case pbkdf2 = 0, argon2id = 1 }
    var kind: Kind
    var iterations: Int
    var memory: Int? = nil
    var parallelism: Int? = nil
    func validate() throws {
        switch kind {
        case .pbkdf2: guard iterations >= 5_000 && iterations <= 2_000_000 else { throw VaultCryptoError.unsupportedKDF }
        case .argon2id:
            guard iterations >= 2 && iterations <= 10, let memory, (15...1024).contains(memory), let parallelism, (1...16).contains(parallelism) else { throw VaultCryptoError.unsupportedKDF }
        }
    }
}

enum VaultCrypto {
    static func random(_ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        precondition(status == errSecSuccess, "No system randomness")
        return data
    }
    static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
    static func hmac(_ data: Data, key: Data) -> Data { Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))) }
    static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
    static func hkdfExpand(_ key: Data, info: String, count: Int = 32) -> Data {
        HKDF<SHA256>.expand(pseudoRandomKey: SymmetricKey(data: key), info: Data(info.utf8), outputByteCount: count).withUnsafeBytes { Data($0) }
    }
    static func pbkdf2(_ password: Data, salt: Data, iterations: Int, count: Int = 32) -> Data {
        var output = Data(count: count)
        let status = output.withUnsafeMutableBytes { out in
            password.withUnsafeBytes { pass in
                salt.withUnsafeBytes { salt in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.bindMemory(to: CChar.self).baseAddress, password.count,
                                         salt.bindMemory(to: UInt8.self).baseAddress, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                         UInt32(iterations), out.bindMemory(to: UInt8.self).baseAddress, count)
                }
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed")
        return output
    }
    static func aes(_ input: Data, key: Data, iv: Data, operation: CCOperation) throws -> Data {
        guard key.count == 32, iv.count == 16 else { throw VaultCryptoError.invalidKey }
        var output = Data(count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let capacity = output.count
        let status = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { input in
                key.withUnsafeBytes { key in
                    iv.withUnsafeBytes { iv in
                        CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), key.baseAddress, key.count, iv.baseAddress,
                                input.baseAddress, input.count, out.baseAddress, capacity, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw VaultCryptoError.decryptionFailed }
        return output.prefix(moved)
    }

    /// The master key derived from the master password. The salt is the account's email unless the server supplies one.
    static func masterKey(password: String, salt: String, kdf: VaultKDF) throws -> Data {
        try kdf.validate()
        let password = Data(password.utf8), salt = Data(salt.utf8)
        switch kdf.kind {
        case .pbkdf2: return pbkdf2(password, salt: salt, iterations: kdf.iterations)
        case .argon2id:
            return Argon2.hash(password: password, salt: sha256(salt), iterations: kdf.iterations, memoryKiB: kdf.memory! * 1024, parallelism: kdf.parallelism!, length: 32)
        }
    }
    /// The value sent to the server in place of the master password. It can't be used to decrypt the vault.
    static func serverHash(masterKey: Data, password: String) -> String {
        pbkdf2(masterKey, salt: Data(password.utf8), iterations: 1).base64EncodedString()
    }
    static func stretch(_ masterKey: Data) -> VaultKey {
        VaultKey(encryption: hkdfExpand(masterKey, info: "enc"), mac: hkdfExpand(masterKey, info: "mac"))
    }
    /// Opens the account's user key. Very old accounts encrypted it with the unstretched master key.
    static func userKey(_ protected: String, masterKey: Data) throws -> VaultKey {
        let encrypted = try EncString(protected)
        let key = encrypted.kind == .aesCbc256 ? try VaultKey(masterKey) : stretch(masterKey)
        return try VaultKey(encrypted.decrypt(key))
    }
    /// Imports a PKCS #8 RSA private key, as stored by Bitwarden.
    static func privateKey(pkcs8 data: Data) throws -> SecKey {
        let pkcs1 = try DER.pkcs1(fromPKCS8: data)
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil) else { throw VaultCryptoError.invalidKey }
        return key
    }
}

/// Just enough DER to unwrap PKCS #8, which the Security framework won't import directly.
enum DER {
    static func pkcs1(fromPKCS8 data: Data) throws -> Data {
        var reader = Reader(bytes: [UInt8](data))
        var info = Reader(bytes: try reader.element(0x30))
        _ = try info.element(0x02)                  // version
        _ = try info.element(0x30)                  // algorithm identifier
        return Data(try info.element(0x04))         // RSAPrivateKey
    }
    /// Wraps a PKCS #1 RSA key as PKCS #8.
    static func pkcs8(fromPKCS1 key: Data) -> Data {
        let algorithm: [UInt8] = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00]
        let body = [0x02, 0x01, 0x00] + algorithm + element(0x04, [UInt8](key))
        return Data(element(0x30, body))
    }
    static func element(_ tag: UInt8, _ body: [UInt8]) -> [UInt8] {
        var length: [UInt8] = []
        if body.count < 0x80 { length = [UInt8(body.count)] } else {
            var count = body.count
            while count > 0 { length.insert(UInt8(count & 0xff), at: 0); count >>= 8 }
            length.insert(0x80 | UInt8(length.count), at: 0)
        }
        return [tag] + length + body
    }
    struct Reader {
        var bytes: [UInt8]
        var offset = 0
        mutating func element(_ tag: UInt8) throws -> [UInt8] {
            guard offset + 2 <= bytes.count, bytes[offset] == tag else { throw VaultCryptoError.invalidKey }
            var length = Int(bytes[offset + 1]); offset += 2
            if length & 0x80 != 0 {
                let count = length & 0x7f
                guard count > 0, count <= 4, offset + count <= bytes.count else { throw VaultCryptoError.invalidKey }
                length = bytes[offset..<offset + count].reduce(0) { $0 << 8 | Int($1) }; offset += count
            }
            guard offset + length <= bytes.count else { throw VaultCryptoError.invalidKey }
            defer { offset += length }
            return Array(bytes[offset..<offset + length])
        }
    }
}

/// Time-based one-time passwords (RFC 6238), including Steam Guard codes.
struct TOTP: Equatable {
    enum Algorithm: String { case sha1 = "SHA1", sha256 = "SHA256", sha512 = "SHA512" }
    var secret: Data
    var algorithm = Algorithm.sha1
    var digits = 6
    var period = 30
    var steam = false
    init(secret: Data, algorithm: Algorithm = .sha1, digits: Int = 6, period: Int = 30, steam: Bool = false) {
        self.secret = secret; self.algorithm = algorithm; self.digits = digits; self.period = period; self.steam = steam
    }
    /// Accepts `otpauth://totp/…` URIs, `steam://` secrets, or a bare Base32 key.
    init(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("otpauth://") {
            guard let components = URLComponents(string: trimmed), components.host?.lowercased() == "totp" else { throw VaultCryptoError.invalidTOTP }
            let query = Dictionary((components.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") }) { first, _ in first }
            guard let secret = query["secret"].flatMap(Base32.decode), !secret.isEmpty else { throw VaultCryptoError.invalidTOTP }
            self.secret = secret
            if let name = query["algorithm"] { guard let algorithm = Algorithm(rawValue: name.uppercased()) else { throw VaultCryptoError.invalidTOTP }; self.algorithm = algorithm }
            if let digits = query["digits"] { guard let value = Int(digits), (1...10).contains(value) else { throw VaultCryptoError.invalidTOTP }; self.digits = value }
            if let period = query["period"] { guard let value = Int(period), value > 0 else { throw VaultCryptoError.invalidTOTP }; self.period = value }
        } else if trimmed.lowercased().hasPrefix("steam://") {
            guard let secret = Base32.decode(String(trimmed.dropFirst(8))), !secret.isEmpty else { throw VaultCryptoError.invalidTOTP }
            self.secret = secret; digits = 5; steam = true
        } else {
            guard let secret = Base32.decode(trimmed), !secret.isEmpty else { throw VaultCryptoError.invalidTOTP }
            self.secret = secret
        }
    }
    func code(at date: Date = Date()) -> String {
        var counter = UInt64(max(0, date.timeIntervalSince1970) / Double(period)).bigEndian
        let message = Data(bytes: &counter, count: 8), key = SymmetricKey(data: secret)
        let digest: [UInt8]
        switch algorithm {
        case .sha1: digest = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: digest = Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: digest = Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
        let offset = Int(digest[digest.count - 1] & 0x0f)
        var value = (UInt32(digest[offset] & 0x7f) << 24 | UInt32(digest[offset + 1]) << 16 | UInt32(digest[offset + 2]) << 8 | UInt32(digest[offset + 3]))
        if steam {
            let alphabet = Array("23456789BCDFGHJKMNPQRTVWXY")
            var code = ""
            for _ in 0..<digits { code.append(alphabet[Int(value % UInt32(alphabet.count))]); value /= UInt32(alphabet.count) }
            return code
        }
        let modulus = (0..<digits).reduce(UInt64(1)) { value, _ in value * 10 }
        let code = String(UInt64(value) % modulus)
        return String(repeating: "0", count: max(0, digits - code.count)) + code
    }
    func remaining(at date: Date = Date()) -> Int { period - Int(date.timeIntervalSince1970) % period }
}

enum Base32 {
    static func decode(_ string: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var buffer = 0, bits = 0, output = Data()
        for character in string.uppercased() where character != "=" && character != " " && character != "-" {
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            buffer = buffer << 5 | index; bits += 5
            if bits >= 8 { bits -= 8; output.append(UInt8(buffer >> bits & 0xff)) }
            buffer &= (1 << bits) - 1
        }
        return output
    }
}

/// BLAKE2b (RFC 7693), unkeyed, used by Argon2.
struct Blake2b {
    private static let iv: [UInt64] = [0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
                                       0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179]
    private static let sigma: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
        [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4], [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
        [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13], [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
        [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11], [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
        [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5], [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0]]
    private var h: [UInt64]
    private var buffer: [UInt8] = []
    private var counter: UInt64 = 0
    let length: Int
    init(length: Int) {
        precondition((1...64).contains(length))
        self.length = length
        h = Self.iv
        h[0] ^= 0x01010000 ^ UInt64(length)
    }
    mutating func update(_ bytes: [UInt8]) {
        for byte in bytes {
            // The final block is compressed in finalize, so only flush once more input follows a full buffer.
            if buffer.count == 128 { counter &+= 128; compress(buffer, last: false); buffer.removeAll(keepingCapacity: true) }
            buffer.append(byte)
        }
    }
    mutating func update(_ value: UInt32) { update([UInt8(value & 0xff), UInt8(value >> 8 & 0xff), UInt8(value >> 16 & 0xff), UInt8(value >> 24)]) }
    mutating func finalize() -> [UInt8] {
        counter &+= UInt64(buffer.count)
        compress(buffer + [UInt8](repeating: 0, count: 128 - buffer.count), last: true)
        return Array(h.flatMap { word in (0..<8).map { UInt8(word >> (8 * $0) & 0xff) } }.prefix(length))
    }
    static func hash(_ bytes: [UInt8], length: Int = 64) -> [UInt8] { var hasher = Blake2b(length: length); hasher.update(bytes); return hasher.finalize() }
    private mutating func compress(_ block: [UInt8], last: Bool) {
        var m = [UInt64](repeating: 0, count: 16)
        for i in 0..<16 { for b in 0..<8 { m[i] |= UInt64(block[i * 8 + b]) << (8 * b) } }
        var v = h + Self.iv
        v[12] ^= counter
        if last { v[14] = ~v[14] }
        func g(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt64, _ y: UInt64) {
            v[a] = v[a] &+ v[b] &+ x; v[d] = (v[d] ^ v[a]).rotatedRight(32)
            v[c] = v[c] &+ v[d]; v[b] = (v[b] ^ v[c]).rotatedRight(24)
            v[a] = v[a] &+ v[b] &+ y; v[d] = (v[d] ^ v[a]).rotatedRight(16)
            v[c] = v[c] &+ v[d]; v[b] = (v[b] ^ v[c]).rotatedRight(63)
        }
        for round in 0..<12 {
            let s = Self.sigma[round % 10]
            g(0, 4, 8, 12, m[s[0]], m[s[1]]); g(1, 5, 9, 13, m[s[2]], m[s[3]])
            g(2, 6, 10, 14, m[s[4]], m[s[5]]); g(3, 7, 11, 15, m[s[6]], m[s[7]])
            g(0, 5, 10, 15, m[s[8]], m[s[9]]); g(1, 6, 11, 12, m[s[10]], m[s[11]])
            g(2, 7, 8, 13, m[s[12]], m[s[13]]); g(3, 4, 9, 14, m[s[14]], m[s[15]])
        }
        for i in 0..<8 { h[i] ^= v[i] ^ v[i + 8] }
    }
}

extension UInt64 {
    @inline(__always) func rotatedRight(_ count: UInt64) -> UInt64 { self >> count | self << (64 - count) }
}

/// Argon2id version 1.3 (RFC 9106), single-threaded.
enum Argon2 {
    private static let words = 128
    static func hash(password: Data, salt: Data, iterations: Int, memoryKiB: Int, parallelism: Int, length: Int, secret: Data = Data(), associated: Data = Data()) -> Data {
        var h0 = Blake2b(length: 64)
        for value in [parallelism, length, memoryKiB, iterations, 0x13, 2] { h0.update(UInt32(value)) }
        for data in [password, salt, secret, associated] { h0.update(UInt32(data.count)); h0.update([UInt8](data)) }
        let seed = h0.finalize()
        let lanes = parallelism
        let blockCount = max(memoryKiB, 8 * lanes) / (4 * lanes) * (4 * lanes)
        let laneLength = blockCount / lanes, segmentLength = laneLength / 4
        let memory = UnsafeMutablePointer<UInt64>.allocate(capacity: blockCount * words)
        memory.initialize(repeating: 0, count: blockCount * words)
        defer { memory.deinitialize(count: blockCount * words); memory.deallocate() }
        func block(_ index: Int) -> UnsafeMutablePointer<UInt64> { memory + index * words }
        for lane in 0..<lanes {
            for column in 0..<2 {
                let bytes = variableHash(seed + le32(column) + le32(lane), length: 1024)
                load(bytes, into: block(lane * laneLength + column))
            }
        }
        let zero = UnsafeMutablePointer<UInt64>.allocate(capacity: words), input = UnsafeMutablePointer<UInt64>.allocate(capacity: words), address = UnsafeMutablePointer<UInt64>.allocate(capacity: words)
        let scratch = UnsafeMutablePointer<UInt64>.allocate(capacity: 2 * words)
        defer { for pointer in [zero, input, address] { pointer.deallocate() }; scratch.deallocate() }
        zero.initialize(repeating: 0, count: words)
        func nextAddresses() {
            input[6] &+= 1
            compress(previous: zero, reference: input, into: address, xor: false, scratch: scratch)
            compress(previous: zero, reference: address, into: address, xor: false, scratch: scratch)
        }
        for pass in 0..<iterations {
            for slice in 0..<4 {
                for lane in 0..<lanes {
                    let independent = pass == 0 && slice < 2
                    if independent {
                        input.initialize(repeating: 0, count: words)
                        input[0] = UInt64(pass); input[1] = UInt64(lane); input[2] = UInt64(slice)
                        input[3] = UInt64(blockCount); input[4] = UInt64(iterations); input[5] = 2
                    }
                    var start = 0
                    if pass == 0 && slice == 0 { start = 2; if independent { nextAddresses() } }
                    var current = lane * laneLength + slice * segmentLength + start
                    var previous = current % laneLength == 0 ? current + laneLength - 1 : current - 1
                    for index in start..<segmentLength {
                        if current % laneLength == 1 { previous = current - 1 }
                        let random: UInt64
                        if independent {
                            if index % words == 0 { nextAddresses() }
                            random = address[index % words]
                        } else { random = block(previous)[0] }
                        let referenceLane = pass == 0 && slice == 0 ? lane : Int((random >> 32) % UInt64(lanes))
                        let sameLane = referenceLane == lane
                        var area: Int
                        if pass == 0 {
                            area = slice == 0 ? index - 1 : sameLane ? slice * segmentLength + index - 1 : slice * segmentLength - (index == 0 ? 1 : 0)
                        } else {
                            area = sameLane ? laneLength - segmentLength + index - 1 : laneLength - segmentLength - (index == 0 ? 1 : 0)
                        }
                        var relative = random & 0xffff_ffff
                        relative = (relative &* relative) >> 32
                        relative = UInt64(area) - 1 - ((UInt64(area) &* relative) >> 32)
                        let startPosition = pass == 0 || slice == 3 ? 0 : (slice + 1) * segmentLength
                        let referenceIndex = (startPosition + Int(relative)) % laneLength
                        compress(previous: block(previous), reference: block(referenceLane * laneLength + referenceIndex), into: block(current), xor: pass > 0, scratch: scratch)
                        current += 1; previous += 1
                    }
                }
            }
        }
        let final = UnsafeMutablePointer<UInt64>.allocate(capacity: words)
        defer { final.deallocate() }
        final.initialize(from: block(laneLength - 1), count: words)
        for lane in 1..<lanes { for i in 0..<words { final[i] ^= block(lane * laneLength + laneLength - 1)[i] } }
        var bytes = [UInt8](repeating: 0, count: 1024)
        for i in 0..<words { for b in 0..<8 { bytes[i * 8 + b] = UInt8(final[i] >> (8 * b) & 0xff) } }
        return Data(variableHash(bytes, length: length))
    }
    private static func le32(_ value: Int) -> [UInt8] { (0..<4).map { UInt8(value >> (8 * $0) & 0xff) } }
    private static func load(_ bytes: [UInt8], into block: UnsafeMutablePointer<UInt64>) {
        for i in 0..<words { var word: UInt64 = 0; for b in 0..<8 { word |= UInt64(bytes[i * 8 + b]) << (8 * b) }; block[i] = word }
    }
    /// H′, Argon2's variable-length hash.
    static func variableHash(_ input: [UInt8], length: Int) -> [UInt8] {
        let prefixed = le32(length) + input
        guard length > 64 else { return Blake2b.hash(prefixed, length: length) }
        var output: [UInt8] = [], v = Blake2b.hash(prefixed)
        let rounds = (length + 31) / 32 - 2
        for _ in 0..<rounds - 1 { output += v.prefix(32); v = Blake2b.hash(v) }
        output += v.prefix(32)
        output += Blake2b.hash(v, length: length - 32 * rounds)
        return output
    }
    @inline(__always) private static func blamka(_ x: UInt64, _ y: UInt64) -> UInt64 { x &+ y &+ 2 &* ((x & 0xffff_ffff) &* (y & 0xffff_ffff)) }
    @inline(__always) private static func mix(_ v: UnsafeMutablePointer<UInt64>, _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        v[a] = blamka(v[a], v[b]); v[d] = (v[d] ^ v[a]).rotatedRight(32)
        v[c] = blamka(v[c], v[d]); v[b] = (v[b] ^ v[c]).rotatedRight(24)
        v[a] = blamka(v[a], v[b]); v[d] = (v[d] ^ v[a]).rotatedRight(16)
        v[c] = blamka(v[c], v[d]); v[b] = (v[b] ^ v[c]).rotatedRight(63)
    }
    @inline(__always) private static func round(_ v: UnsafeMutablePointer<UInt64>, _ i: [Int]) {
        mix(v, i[0], i[4], i[8], i[12]); mix(v, i[1], i[5], i[9], i[13]); mix(v, i[2], i[6], i[10], i[14]); mix(v, i[3], i[7], i[11], i[15])
        mix(v, i[0], i[5], i[10], i[15]); mix(v, i[1], i[6], i[11], i[12]); mix(v, i[2], i[7], i[8], i[13]); mix(v, i[3], i[4], i[9], i[14])
    }
    private static let rows: [[Int]] = (0..<8).map { r in (0..<16).map { 16 * r + $0 } }
    private static let columns: [[Int]] = (0..<8).map { (c: Int) -> [Int] in (0..<8).flatMap { (r: Int) -> [Int] in [16 * r + 2 * c, 16 * r + 2 * c + 1] } }
    /// Argon2's compression function G. With `xor`, the result is combined with the block's existing contents.
    private static func compress(previous: UnsafeMutablePointer<UInt64>, reference: UnsafeMutablePointer<UInt64>, into next: UnsafeMutablePointer<UInt64>, xor: Bool, scratch: UnsafeMutablePointer<UInt64>) {
        let r = scratch, z = scratch + words
        for i in 0..<words { r[i] = previous[i] ^ reference[i] }
        for i in 0..<words { z[i] = xor ? r[i] ^ next[i] : r[i] }
        for row in rows { round(r, row) }
        for column in columns { round(r, column) }
        for i in 0..<words { next[i] = z[i] ^ r[i] }
    }
}

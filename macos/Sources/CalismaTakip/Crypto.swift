import Foundation
import CryptoKit
import Security
import CTLegacyCrypto
import TakipCore

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
enum Secrets {
    private static let service = "local.calisma-takip.macos.v1"
    static func set(_ value: Data, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecItemNotFound {
            var addition = query; addition[kSecValueData as String] = value
            addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(addition as CFDictionary, nil) == errSecSuccess else { throw AppError.message("Anahtar Anahtar Zinciri’ne yazılamadı.") }
        } else if status != errSecSuccess { throw AppError.message("Anahtar Zinciri güncellenemedi.") }
    }
    static func get(_ account: String) throws -> Data {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { throw AppError.message("Cihaz anahtarı bulunamadı; yeniden eşleştirin.") }
        return data
    }
    static func delete(_ account: String) { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary) }
}
enum Crypto {
    static func random(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw AppError.message("Güvenli rastgele sayı üretilemedi.") }
        return Data(bytes)
    }
    static func derive(code: String, salt: Data, count: Int = 64) throws -> Data {
        let password = Array(Wire.normalizedCode(code).utf8), salt = Array(salt)
        var output = [UInt8](repeating: 0, count: count)
        guard ct_pbkdf2(password, password.count, salt, salt.count, &output, count) == 0 else { throw AppError.message("Eşleşme anahtarı türetilemedi.") }
        return Data(output)
    }
    static func mac(_ data: Data, key: Data) -> Data { Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))) }
    static func signature(key: Data, timestamp: String, body: Data) -> String {
        mac(Data((timestamp + "\n").utf8) + body, key: key).map { String(format: "%02x", $0) }.joined()
    }
    static func equal(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0; for (x, y) in zip(a, b) { diff |= x ^ y }; return diff == 0
    }
    static func crypt(_ data: Data, key: Data, iv: Data, encrypt: Bool) throws -> Data {
        guard key.count == 32, iv.count == 16, data.count <= 4096 else { throw AppError.message("Anahtar paketi boyutu geçersiz.") }
        var output = [UInt8](repeating: 0, count: data.count + 16); var written = 0
        let capacity = output.count
        guard ct_aes(encrypt ? 1 : 0, Array(key), Array(iv), Array(data), data.count, &output, capacity, &written) == 0 else { throw AppError.message("Anahtar paketi çözülemedi.") }
        return Data(output.prefix(written))
    }
    static func seal(key: Data, code: String) throws -> [String: String] {
        let salt = try random(16), iv = try random(16), derived = try derive(code: code, salt: salt)
        let encrypted = try crypt(Data(key.base64EncodedString().utf8), key: Data(derived.prefix(32)), iv: iv, encrypt: true)
        return ["tuz": salt.base64EncodedString(), "iv": iv.base64EncodedString(), "veri": encrypted.base64EncodedString(), "etiket": mac(iv + encrypted, key: Data(derived.suffix(32))).base64EncodedString()]
    }
    static func open(_ packet: [String: Any], code: String) throws -> Data {
        func field(_ name: String) throws -> Data {
            guard let text = packet[name] as? String, text.count < 8192, let data = Data(base64Encoded: text) else { throw AppError.message("Anahtar paketi geçersiz.") }; return data
        }
        let salt = try field("tuz"), iv = try field("iv"), data = try field("veri"), tag = try field("etiket")
        guard salt.count == 16 else { throw AppError.message("Eşleşme tuzu geçersiz.") }
        let derived = try derive(code: code, salt: salt)
        guard equal(mac(iv + data, key: Data(derived.suffix(32))), tag) else { throw AppError.message("Eşleşme kodu veya paket imzası geçersiz.") }
        let plain = try crypt(data, key: Data(derived.prefix(32)), iv: iv, encrypt: false)
        guard let text = String(data: plain, encoding: .utf8), let key = Data(base64Encoded: text), key.count == 32 else { throw AppError.message("Merkez anahtarı geçersiz.") }
        return key
    }
}

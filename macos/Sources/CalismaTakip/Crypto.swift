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
    static func crypt(_ data: Data, key: Data, iv: Data, encrypt: Bool, limit: Int = 4096) throws -> Data {
        guard key.count == 32, iv.count == 16, data.count <= limit else { throw AppError.message("Anahtar paketi boyutu geçersiz.") }
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

/// Protokol v2 zarf anahtarları (uyumluluk/PROTOKOL-V2.md §2).
struct ZarfKeys {
    let encryption: Data
    let signing: Data
    /// Posta kutusu erişim jetonu (küçük harf hex); sunucu yalnızca SHA-256 özetini bilir
    let mailboxToken: String
}

/// Protokol v2 şifreli zarfı. Windows'taki `New-DagitikZarf` / `Open-DagitikZarf` ile bayt bayt
/// aynıdır; `WindowsInteropTests` `zarfV2` ve `kayitV2` vektörleriyle sınar.
enum Zarf {
    struct Enrollment {
        let master: Data
        let channel: String
        let keys: ZarfKeys
    }
    static let maximumPlain = 2 * 1024 * 1024

    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
    static func sha256Hex(_ data: Data) -> String { hex(Data(SHA256.hash(data: data))) }
    private static func derive(_ key: Data, _ label: String) -> Data { Crypto.mac(Data(label.utf8), key: key) }

    static func keys(deviceKey: Data) -> ZarfKeys {
        ZarfKeys(encryption: derive(deviceKey, "Aizen|v2|sifre"), signing: derive(deviceKey, "Aizen|v2|imza"),
                 mailboxToken: hex(derive(deviceKey, "Aizen|v2|posta")))
    }
    static func enrollment(master: Data) -> Enrollment {
        let identity = hex(derive(master, "Aizen|kayit|v2|kimlik"))
        let keys = ZarfKeys(encryption: derive(master, "Aizen|kayit|v2|sifre"), signing: derive(master, "Aizen|kayit|v2|imza"),
                            mailboxToken: hex(derive(master, "Aizen|kayit|v2|posta")))
        return Enrollment(master: master, channel: "k-" + String(identity.prefix(24)), keys: keys)
    }
    /// ana = PBKDF2-HMAC-SHA256(normal kod, "Aizen|kayit|v2", 120000, 32)
    static func enrollment(code: String) throws -> Enrollment {
        guard Wire.normalizedCode(code).count >= 8 else { throw AppError.message("Eşleşme kodu geçersiz.") }
        return enrollment(master: try Crypto.derive(code: code, salt: Data("Aizen|kayit|v2".utf8), count: 32))
    }
    static func isChannel(_ id: String) -> Bool { id.range(of: #"^k-[0-9a-f]{24}$"#, options: .regularExpression) != nil }
    static func isDeviceID(_ id: String) -> Bool { id.range(of: #"^[A-Za-z0-9_-]{3,64}$"#, options: .regularExpression) != nil }

    /// `sayac` ve `zaman` JSON'da tam sayı olmalı (metin, ondalık ve true/false geçersiz).
    static func integerText(_ value: Any?) -> String? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() || CFNumberIsFloatType(number as CFNumber) { return nil }
        let integer = number.int64Value
        guard integer >= 0 else { return nil }
        let text = String(integer)
        return text.count <= 15 ? text : nil
    }

    static func isValid(_ envelope: [String: Any]) -> Bool {
        guard integerText(envelope["v"]) == "2",
              let device = envelope["cihaz"] as? String, isDeviceID(device),
              let kind = envelope["tur"] as? String, kind.range(of: #"^[a-z]{2,16}$"#, options: .regularExpression) != nil,
              let direction = envelope["yon"] as? String, direction == "istek" || direction == "yanit",
              integerText(envelope["sayac"]) != nil, integerText(envelope["zaman"]) != nil else { return false }
        for field in ["iv", "veri", "etiket"] {
            guard let text = envelope[field] as? String, text.range(of: #"^[A-Za-z0-9+/]{4,}={0,2}$"#, options: .regularExpression) != nil else { return false }
        }
        return true
    }

    static func signingInput(device: String, kind: String, direction: String, sequence: String, time: String, iv: String, data: String) -> Data {
        Data(["AIZEN-ZARF-2", device, kind, direction, sequence, time, iv, data].joined(separator: "\n").utf8)
    }

    static func seal(_ plain: Data, keys: ZarfKeys, device: String, kind: String, direction: String, sequence: Int64,
                     time: Int64 = Int64(Date().timeIntervalSince1970), iv fixedIV: Data? = nil) throws -> [String: Any] {
        guard isDeviceID(device), kind.range(of: #"^[a-z]{2,16}$"#, options: .regularExpression) != nil, sequence >= 0 else { throw AppError.message("Zarf bilgisi geçersiz.") }
        let iv: Data
        if let fixedIV { iv = fixedIV } else { iv = try Crypto.random(16) }
        let cipher = try Crypto.crypt(plain, key: keys.encryption, iv: iv, encrypt: true, limit: maximumPlain)
        let ivText = iv.base64EncodedString(), dataText = cipher.base64EncodedString()
        let input = signingInput(device: device, kind: kind, direction: direction, sequence: String(sequence), time: String(time), iv: ivText, data: dataText)
        let tag = Crypto.mac(input, key: keys.signing).base64EncodedString()
        return ["v": 2, "cihaz": device, "tur": kind, "yon": direction, "sayac": sequence, "zaman": time, "iv": ivText, "veri": dataText, "etiket": tag]
    }

    /// Önce etiket sabit zamanlı doğrulanır; tutmazsa çözme denenmez.
    static func open(_ envelope: [String: Any], keys: ZarfKeys) throws -> Data {
        guard isValid(envelope),
              let device = envelope["cihaz"] as? String, let kind = envelope["tur"] as? String, let direction = envelope["yon"] as? String,
              let sequence = integerText(envelope["sayac"]), let time = integerText(envelope["zaman"]),
              let ivText = envelope["iv"] as? String, let dataText = envelope["veri"] as? String, let tagText = envelope["etiket"] as? String,
              let iv = Data(base64Encoded: ivText), let cipher = Data(base64Encoded: dataText), let tag = Data(base64Encoded: tagText),
              iv.count == 16, tag.count == 32, !cipher.isEmpty, cipher.count % 16 == 0 else { throw AppError.message("Zarf biçimi geçersiz.") }
        let expected = Crypto.mac(signingInput(device: device, kind: kind, direction: direction, sequence: sequence, time: time, iv: ivText, data: dataText), key: keys.signing)
        guard Crypto.equal(expected, tag) else { throw AppError.message("Zarf imzası geçersiz.") }
        return try Crypto.crypt(cipher, key: keys.encryption, iv: iv, encrypt: false, limit: maximumPlain + 32)
    }
}

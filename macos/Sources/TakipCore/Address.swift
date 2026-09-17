import Foundation

/// Merkez adresi. Windows'taki `ConvertFrom-DagitikAdres` (dagitik/Ortak.ps1) ile aynı kurallar:
///   http(s)://sunucu[:port]             doğrudan merkez (yerel ağ ya da port yönlendirme)
///   https://sunucu[:port]/k/<kutu>       posta kutusu (kutu: 16–64 hex)
public struct CenterAddress: Equatable {
    public enum Kind: String { case direct = "dogrudan", mailbox = "posta" }
    public let kind: Kind
    /// Şema küçük harfe çevrilmiş `şema://sunucu[:port]`
    public let root: String
    /// Posta kutusu kimliği (küçük harf hex); doğrudan adreste boş
    public let box: String

    public var text: String { kind == .mailbox ? root + "/k/" + box : root }

    public static func parse(_ value: String) -> CenterAddress? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty, text.count <= 300 else { return nil }
        let host = #"^([Hh][Tt][Tt][Pp][Ss]?://[^/\\\s?#@]+)"#
        if let match = firstMatch(host + #"/[Kk]/([0-9A-Fa-f]{16,64})$"#, in: text) {
            return CenterAddress(kind: .mailbox, root: normalizedScheme(match[1]), box: match[2].lowercased())
        }
        if let match = firstMatch(host + "$", in: text) {
            return CenterAddress(kind: .direct, root: normalizedScheme(match[1]), box: "")
        }
        return nil
    }

    /// Posta kutusu jetonları yalnız HTTPS ile gider; düz HTTP yalnız bu bilgisayar için (testler).
    public var isSecureTransport: Bool {
        if root.hasPrefix("https://") { return true }
        return root.range(of: #"^http://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]{1,5})?$"#, options: .regularExpression) != nil
    }

    /// Merkezin kendi döngü adresi başka bir bilgisayardan anlamsızdır.
    public var isLoopback: Bool {
        root.range(of: #"^https?://(127\.|localhost(:|$)|\[::1\])"#, options: .regularExpression) != nil
    }

    /// Merkezin şifreli yanıtla bildirdiği adresleri mevcut listeyle birleştirir
    /// (Windows: `Update-IstemciAdresleri`). Çalışan adres başta kalır, merkezin bildirdiği döngü
    /// adresi alınmaz, en çok 4 doğrudan adres tutulur; geçerli bir posta kutusu adresi eskisinin yerine geçer.
    public static func merge(reported: [String: Any]?, direct current: [String], mailbox currentMailbox: String?, used: String?) -> (direct: [String], mailbox: String?) {
        guard let reported else { return (current, currentMailbox) }
        var candidates: [(value: String, fromCenter: Bool)] = []
        if let used { candidates.append((used, false)) }
        if let server = reported["sunucuUrl"] as? String { candidates.append((server, true)) }
        for extra in reported["ekAdresler"] as? [String] ?? [] { candidates.append((extra, true)) }
        for existing in current { candidates.append((existing, false)) }
        var result: [String] = []
        for candidate in candidates {
            guard result.count < 4, let address = parse(candidate.value), address.kind == .direct, !result.contains(address.text) else { continue }
            if candidate.fromCenter && address.isLoopback { continue }
            result.append(address.text)
        }
        var mailbox = currentMailbox
        if let text = reported["postaUrl"] as? String, let address = parse(text), address.kind == .mailbox, address.isSecureTransport {
            mailbox = address.text
        }
        return (result, mailbox)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        var groups: [String] = []
        for index in 0..<match.numberOfRanges {
            if let range = Range(match.range(at: index), in: text) { groups.append(String(text[range])) } else { groups.append("") }
        }
        return groups
    }

    private static func normalizedScheme(_ root: String) -> String {
        guard let separator = root.range(of: "://") else { return root }
        return String(root[..<separator.lowerBound]).lowercased() + String(root[separator.lowerBound...])
    }
}

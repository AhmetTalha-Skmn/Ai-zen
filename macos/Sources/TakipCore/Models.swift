import Foundation

public enum RuleKind: String, Codable, CaseIterable, Identifiable {
    case process = "surec", title = "baslik", domain = "alanadi"
    public var id: String { rawValue }
    public var label: String { switch self { case .process: return "Uygulama"; case .title: return "Tam pencere başlığı"; case .domain: return "Alan adı" } }
}
public enum Decision: String, Codable, CaseIterable, Identifiable {
    case work = "calisma", forbidden = "yasakli", uncertain = "belirsiz"
    public var id: String { rawValue }
    public var label: String { switch self { case .work: return "İzinli"; case .forbidden: return "İzinsiz"; case .uncertain: return "Belirsiz" } }
}
public enum Category: String, Codable { case work = "calisma", other = "diger", idle = "bosta", uncertain = "belirsiz" }
public struct RuleGroup: Codable, Equatable {
    public var surec: [String] = []
    public var baslik: [String] = []
    public var alanadi: [String] = []
    public init() {}
    public subscript(_ kind: RuleKind) -> [String] {
        get { switch kind { case .process: return surec; case .title: return baslik; case .domain: return alanadi } }
        set { switch kind { case .process: surec = newValue; case .title: baslik = newValue; case .domain: alanadi = newValue } }
    }
}
public struct RuleChange: Codable, Identifiable, Equatable {
    public var id: UUID
    public var oge: String
    public var tur: RuleKind
    public var karar: Decision
    public var rowKey: String { tur.rawValue + "|" + karar.rawValue + "|" + oge }
    public init(value: String, kind: RuleKind, decision: Decision) { id = UUID(); oge = value; tur = kind; karar = decision }
    enum CodingKeys: String, CodingKey { case id, oge, tur, karar }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        oge = try c.decode(String.self, forKey: .oge)
        tur = try c.decode(RuleKind.self, forKey: .tur)
        karar = try c.decode(Decision.self, forKey: .karar)
    }
}
public struct Rules: Codable, Equatable {
    public var calisma = RuleGroup()
    public var yasakli = RuleGroup()
    public var bilerekBelirsiz: [String] = []
    public var belirsizSayilsin = true
    public var aslaEngelleme = ["Finder", "Dock", "SystemUIServer", "loginwindow", "WindowServer", "CalismaTakip", "System Settings", "com.apple.systempreferences", "com.apple.finder", "local.calisma-takip.macos"]
    public init() {}
    enum CodingKeys: String, CodingKey { case calisma, yasakli, bilerekBelirsiz, belirsizSayilsin, aslaEngelleme }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        calisma = try c.decode(RuleGroup.self, forKey: .calisma)
        yasakli = try c.decode(RuleGroup.self, forKey: .yasakli)
        bilerekBelirsiz = try c.decodeIfPresent([String].self, forKey: .bilerekBelirsiz) ?? []
        belirsizSayilsin = try c.decodeIfPresent(Bool.self, forKey: .belirsizSayilsin) ?? true
        aslaEngelleme = try c.decodeIfPresent([String].self, forKey: .aslaEngelleme) ?? Rules().aslaEngelleme
    }
    public mutating func apply(_ change: RuleChange) {
        let value = change.oge.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 160 else { return }
        calisma[change.tur].removeAll { equivalent($0, value) }
        yasakli[change.tur].removeAll { equivalent($0, value) }
        bilerekBelirsiz.removeAll { equivalent($0, value) }
        switch change.karar {
        case .work: calisma[change.tur].append(value)
        case .forbidden: yasakli[change.tur].append(value)
        case .uncertain: bilerekBelirsiz.append(value)
        }
    }
    public mutating func remove(_ change: RuleChange) {
        switch change.karar {
        case .work: calisma[change.tur].removeAll { equivalent($0, change.oge) }
        case .forbidden: yasakli[change.tur].removeAll { equivalent($0, change.oge) }
        case .uncertain: bilerekBelirsiz.removeAll { equivalent($0, change.oge) }
        }
    }
    public mutating func merge(_ shared: SharedRules) {
        for kind in RuleKind.allCases {
            for value in shared.calisma[kind] { apply(RuleChange(value: value, kind: kind, decision: .work)) }
            for value in shared.yasakli[kind] { apply(RuleChange(value: value, kind: kind, decision: .forbidden)) }
        }
        for value in shared.bilerekBelirsiz {
            // The Windows wire format does not carry a kind for intentional uncertainty.
            for kind in RuleKind.allCases {
                calisma[kind].removeAll { equivalent($0, value) }
                yasakli[kind].removeAll { equivalent($0, value) }
            }
            apply(RuleChange(value: value, kind: .process, decision: .uncertain))
        }
        for change in shared.silinenKurallar ?? [] { remove(change) }
        // aslaEngelleme and belirsizSayilsin are deliberately device-local.
    }
    public var rows: [RuleChange] {
        var result: [RuleChange] = []
        for kind in RuleKind.allCases {
            result += calisma[kind].map { RuleChange(value: $0, kind: kind, decision: .work) }
            result += yasakli[kind].map { RuleChange(value: $0, kind: kind, decision: .forbidden) }
        }
        return result + bilerekBelirsiz.map { RuleChange(value: $0, kind: .process, decision: .uncertain) }
    }
}
public struct SharedRules: Codable {
    public var ok: Bool
    public var sonDegisiklikUtc: String
    public var calisma: RuleGroup
    public var yasakli: RuleGroup
    public var bilerekBelirsiz: [String]
    public var silinenKurallar: [RuleChange]?
    public init(rules: Rules, deleted: [RuleChange] = []) {
        ok = true; sonDegisiklikUtc = ""; calisma = rules.calisma; yasakli = rules.yasakli
        bilerekBelirsiz = rules.bilerekBelirsiz; silinenKurallar = deleted
    }
}
public func equivalent(_ a: String, _ b: String) -> Bool {
    a.compare(b, options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX")) == .orderedSame
}
public struct Sample: Codable {
    public var time: Date
    public var app: String
    public var bundle: String
    public var title: String
    public var domain: String
    public var idleSeconds: Double
    public init(time: Date = Date(), app: String, bundle: String = "", title: String = "", domain: String = "", idleSeconds: Double = 0) {
        self.time = time; self.app = app; self.bundle = bundle; self.title = title; self.domain = domain; self.idleSeconds = idleSeconds
    }
}
public struct Classification: Equatable {
    public var category: Category
    public var counted: Bool
    public var mayBlock: Bool
}
/// Windows'taki kurulum türüyle aynı anlam (hatirlatici/ozellikler.ps1).
public enum InstallType: String, CaseIterable, Identifiable {
    case individual = "bireysel", company = "sirket", custom = "ozel"
    public var id: String { rawValue }
    public var label: String { switch self { case .individual: return "Bireysel"; case .company: return "Şirket"; case .custom: return "Özel" } }
    /// Şirket kurulumunda hatırlatma yoktur.
    public var defaultReminders: Bool { self != .company }
    public var defaultScreenLock: Bool { self == .individual }
}
public struct Settings: Codable {
    public var targetMinutes = 240
    public var pauseUntil: Date?
    public var paused = false
    public var focusUntil: Date?
    public var lastReminder: Date?
    public var lastBackup: Date?
    public var retentionDays = 90
    // Kurulum türü ve özellik seçimleri. Eski state.json'da yoktur: nil -> bireysel ve türün varsayılanı.
    // Tür metin olarak tutulur; bilinmeyen değer çözümlemeyi bozmaz, bireysel sayılır.
    public var installType: String?
    public var reminders: Bool?
    public var screenLock: Bool?
    public init() {}
    public func isPaused(at date: Date) -> Bool { paused || (pauseUntil.map { $0 > date } ?? false) }
    public var effectiveInstallType: InstallType { installType.flatMap { InstallType(rawValue: $0.lowercased()) } ?? .individual }
    public var remindersAvailable: Bool { effectiveInstallType != .company }
    public var remindersEnabled: Bool { remindersAvailable && (reminders ?? effectiveInstallType.defaultReminders) }
    public var screenLockEnabled: Bool { screenLock ?? effectiveInstallType.defaultScreenLock }
}
public struct AppTotal: Codable, Identifiable {
    public var id: String
    public var name: String
    public var category: Category
    public var seconds: Double
}
public struct UnknownItem: Codable, Identifiable {
    public var id: String
    public var app: String
    public var title: String
    public var domain: String
    public var seconds: Double
}
public struct Day: Codable {
    public var date: String
    public var workSeconds: Double = 0
    public var otherSeconds: Double = 0
    public var idleSeconds: Double = 0
    public var applications: [String: AppTotal] = [:]
    public var unknown: [String: UnknownItem] = [:]
    public var lastSample: Date?
    public init(date: String) { self.date = date }
    public var minutes: Int { Int(workSeconds / 60) }
    public mutating func add(_ sample: Sample, seconds: Double, classification: Classification) {
        let amount = max(0, min(seconds, 20))
        if classification.counted { workSeconds += amount }
        else if classification.category == .idle { idleSeconds += amount }
        else { otherSeconds += amount }
        let category: Category = classification.counted ? .work : classification.category == .idle ? .idle : .other
        let key = sample.bundle + "|" + sample.app + "|" + category.rawValue
        var total = applications[key] ?? AppTotal(id: key, name: sample.app, category: category, seconds: 0)
        total.seconds += amount; applications[key] = total
        if classification.category == .uncertain {
            let key = sample.app + "|" + sample.title + "|" + sample.domain
            if unknown[key] != nil || unknown.count < 200 {
                var item = unknown[key] ?? UnknownItem(id: key, app: sample.app, title: sample.title, domain: sample.domain, seconds: 0)
                item.seconds += amount; unknown[key] = item
            }
        }
        lastSample = sample.time
    }
}
public struct Connection: Codable {
    public var server: String
    public var deviceID: String
    public var deviceName: String
    public var consentAt: Date
    public var sequence: Int = 0
    public var lastSuccess: Date?
    public var lastRuleSuccess: Date?
    public var lastError: String = ""
    // Protokol v2 (uyumluluk/PROTOKOL-V2.md). Eski state.json'da yoktur: nil = v1 bağlantı.
    public var protocolVersion: Int?
    /// Sırayla denenen doğrudan adresler (yerel ağ, internet)
    public var directAddresses: [String]?
    /// Doğrudan adreslere ulaşılamazsa kullanılan posta kutusu (https://sunucu/k/kutu)
    public var mailbox: String?
    /// Zarf sayacı; her zarfta artar ve göndermeden önce kaydedilir
    public var counter: Int64?
    public var lastChannel: String?
    /// Posta kutusundan tür başına işlenen en büyük yanıt sayacı (eski yanıt yenisini geri almasın)
    public var mailboxLastResponse: [String: Int64]?
    public var mailboxAwaiting: Bool?
    public init(server: String, deviceID: String, deviceName: String, consentAt: Date) {
        self.server = server; self.deviceID = deviceID; self.deviceName = deviceName; self.consentAt = consentAt
    }
}
public struct SharedTotal: Codable {
    public var date: String
    public var otherMinutes: Int
    public var updated: Date
    public init(date: String, otherMinutes: Int, updated: Date) { self.date = date; self.otherMinutes = otherMinutes; self.updated = updated }
    public func usableMinutes(now: Date) -> Int {
        guard date == dayKey(now), now.timeIntervalSince(updated) >= -60, now.timeIntervalSince(updated) <= 1800 else { return 0 }
        return max(0, min(1440, otherMinutes))
    }
}
// "State" adı SwiftUI'nin @State sarmalayıcısıyla çakışır (SwiftUI ve TakipCore'u birlikte
// içe aktaran dosyalarda "ambiguous for type lookup"). JSON alan adları değişmez.
public struct TrackerState: Codable {
    public var version = 1
    public var settings = Settings()
    public var rules = Rules()
    public var days: [String: Day] = [:]
    public var connection: Connection?
    public var pending: [RuleChange] = []
    public var dirtyDays: [String] = []
    public var sharedTotal: SharedTotal?
    public init() {}
}
public func dayKey(_ date: Date, timeZone: TimeZone = .current) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}
public func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

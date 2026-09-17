import Foundation
import Combine
import TakipCore

// Injectable credential store lets protocol tests run without touching the user's Keychain.
struct CenterCredentials {
    var read: (String) throws -> Data = { try Secrets.get($0) }
    var write: (Data, String) throws -> Void = { try Secrets.set($0, account: $1) }
    var remove: (String) -> Void = { Secrets.delete($0) }
}

struct CenterDevice: Codable, Identifiable {
    var id: String
    var name: String
    var active = true
    var canWriteRules = false
    var target = 240
    var salt = Data()
    var codeHash = Data()
    var expires: Date?
    var consent: Date?
}
struct CenterApp: Codable, Identifiable {
    var id: String { name + "|" + category }
    var name: String
    var minutes: Int
    var category: String
}
struct CenterReport: Codable {
    var deviceID: String
    var day: String
    var received: Date
    var sent: Date
    var sequence: Int
    var work: Int
    var other: Int
    var idle: Int
    var target: Int
    var apps: [CenterApp]
    var pendingRules: Int?
    var syncError: String
}
struct CenterState: Codable {
    var version = 1
    var enabled = false
    var port: UInt16 = 8787
    var lan = false
    var target = 240
    var devices: [CenterDevice] = []
    var rules = Rules()
    var deleted: [RuleChange] = []
    var ruleVersion = iso(Date())
    var reports: [String: [String: CenterReport]] = [:]
}
@MainActor final class Center: ObservableObject {
    @Published private(set) var state: CenterState
    @Published var status = "Merkez kapalı"
    private let storage: Storage
    private let credentials: CenterCredentials
    private let server = HTTPServer()
    private var attempts: [Date] = []
    init(storage: Storage, credentials: CenterCredentials = CenterCredentials()) throws {
        self.credentials = credentials
        self.storage = storage; state = try storage.load("center-state.json", default: CenterState())
        guard state.version == 1 else { throw AppError.message("Merkez veri sürümü desteklenmiyor; dosya korundu.") }
        server.handler = { [weak self] in self?.handle($0) ?? .error(503, "Merkez hazır değil.") }
        server.statusChanged = { [weak self] in self?.status = $0 }
        if state.enabled { try server.start(port: state.port, lan: state.lan) }
    }
    func commit(_ next: CenterState) throws { try storage.save(next, name: "center-state.json"); state = next }
    private func nextRuleVersion() -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let previous = formatter.date(from: state.ruleVersion) ?? .distantPast
        return formatter.string(from: max(Date(), previous.addingTimeInterval(0.01)))
    }
    func configure(enabled: Bool, port: UInt16, lan: Bool, target: Int) throws {
        guard port >= 1024, (1...1440).contains(target) else { throw AppError.message("Port 1024–65535, hedef 1–1440 aralığında olmalı.") }
        var next = state; next.enabled = enabled; next.port = port; next.lan = lan; next.target = target
        // Persist the intended state before replacing the listener.
        try commit(next); server.stop()
        if enabled { try server.start(port: port, lan: lan) }
    }
    func code(name: String, deviceID: String? = nil) throws -> String {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.message("Cihaz adı boş olamaz.") }
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        let raw = try Crypto.random(12).map { alphabet[Int($0) & 31] }
        let code = stride(from: 0, to: 12, by: 4).map { String(raw[$0..<($0+4)]) }.joined(separator: "-")
        var next = state
        let existing = deviceID.flatMap { id in next.devices.firstIndex { $0.id == id } }
        var device = existing.map { next.devices[$0] } ?? CenterDevice(id: "mac-" + UUID().uuidString.lowercased(), name: String(name.prefix(80)))
        device.salt = try Crypto.random(16); device.codeHash = try Crypto.derive(code: code, salt: device.salt, count: 32)
        device.expires = Date().addingTimeInterval(3600)
        if let existing { next.devices[existing] = device } else { next.devices.append(device) }
        try commit(next); return code
    }
    func updateDevice(_ device: CenterDevice) throws {
        var next = state
        guard let index = next.devices.firstIndex(where: { $0.id == device.id }) else { return }
        guard (1...1440).contains(device.target) else { throw AppError.message("Cihaz hedefi 1–1440 dk olmalı.") }
        next.devices[index].active = device.active; next.devices[index].canWriteRules = device.canWriteRules; next.devices[index].target = device.target
        try commit(next)
    }
    func rule(_ change: RuleChange, remove: Bool = false) throws {
        guard !change.oge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, change.oge.count <= 160 else { throw AppError.message("Kural 1–160 karakter olmalı.") }
        var next = state
        next.deleted.removeAll { equivalent($0.oge, change.oge) && $0.tur == change.tur }
        if remove { next.rules.remove(change); next.deleted.append(change) }
        else { next.rules.apply(change) }
        next.ruleVersion = nextRuleVersion()
        try commit(next)
    }
    func total(day: String) -> Int { (state.reports[day] ?? [:]).values.reduce(0) { $0 + $1.work } }
    func handle(_ request: IncomingRequest) -> ServerResponse {
        do { return try route(request) }
        catch { return .error(500, "Merkez isteği tamamlayamadı; yerel veri veya Anahtar Zinciri erişimini kontrol edin.") }
    }
    private func route(_ request: IncomingRequest) throws -> ServerResponse {
        let path = request.target.components(separatedBy: "?")[0]
        if path == "/health", request.method == "GET" { return ServerResponse(json: ["ok": true, "zamanUtc": iso(Date())]) }
        if path == "/v1/kayit", request.method == "POST" { return try enroll(request) }
        guard let id = request.headers["x-ct-cihaz"], let device = state.devices.first(where: { $0.id == id && $0.active && $0.consent != nil }), let timestamp = request.headers["x-ct-zaman"], let time = TimeInterval(timestamp), abs(Date().timeIntervalSince1970 - time) <= 900, let given = request.headers["x-ct-imza"], given.count == 64, let key = try? credentials.read("center:" + id) else { return .error(401, "Cihaz veya zaman damgası geçersiz.") }
        let signed = request.method == "GET" ? Data(request.target.utf8) : request.body
        let expected = Crypto.signature(key: key, timestamp: timestamp, body: signed)
        guard Crypto.equal(Data(given.lowercased().utf8), Data(expected.utf8)) else { return .error(401, "İmza geçersiz.") }
        switch (request.method, path) {
        case ("GET", "/v1/kurallar"):
            let rules = SharedRules(rules: state.rules, deleted: state.deleted)
            var json = try JSONSerialization.jsonObject(with: storage.encoder.encode(rules)) as! [String: Any]
            json["sonDegisiklikUtc"] = state.ruleVersion; json["kuralSayisi"] = state.rules.rows.count
            return ServerResponse(json: json)
        case ("POST", "/v1/kural"):
            guard device.canWriteRules else { return .error(403, "Bu cihazın kural yazma izni yok.") }
            guard let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any], body["schemaVersion"] as? Int == 1, let decisions = body["kararlar"] as? [[String: Any]], decisions.count <= 200 else { return .error(400, "Kural şeması geçersiz.") }
            var next = state; var count = 0; var invalid = 0
            for raw in decisions {
                guard let value = raw["oge"] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 160, let kind = RuleKind(rawValue: raw["tur"] as? String ?? ""), let decision = Decision(rawValue: raw["karar"] as? String ?? "") else { invalid += 1; continue }
                let change = RuleChange(value: value, kind: kind, decision: decision)
                next.rules.apply(change); next.deleted.removeAll { equivalent($0.oge, value) && $0.tur == kind }; count += 1
            }
            if count > 0 { next.ruleVersion = nextRuleVersion(); try commit(next) }
            return ServerResponse(json: ["ok": true, "islenen": count, "hatali": invalid, "sonDegisiklikUtc": state.ruleVersion])
        case ("GET", "/v1/toplam"):
            let day = URLComponents(string: "http://localhost" + request.target)?.queryItems?.first(where: { $0.name == "tarih" })?.value ?? dayKey(Date())
            guard Storage.dateName(day) else { return .error(400, "Tarih geçersiz.") }
            let reports = state.reports[day] ?? [:], sum = total(day: day), own = reports[id]?.work ?? 0
            let others: [[String: Any]] = reports.values.filter { $0.deviceID != id }.map { report in ["cihazId": report.deviceID, "ad": state.devices.first(where: { $0.id == report.deviceID })?.name ?? report.deviceID, "calismaDk": report.work] }
            return ServerResponse(json: ["ok": true, "tarih": day, "toplamDk": sum, "buCihazDk": own, "digerCihazDk": sum-own, "cihazSayisi": reports.count, "cihazlar": others])
        case ("POST", "/v1/ozet"): return try summary(request, device: device)
        default: return .error(404, "Uç nokta bulunamadı.")
        }
    }
    private func enroll(_ request: IncomingRequest) throws -> ServerResponse {
        attempts.removeAll { Date().timeIntervalSince($0) > 600 }
        guard attempts.count < 20 else { return .error(429, "Çok fazla kayıt denemesi.") }; attempts.append(Date())
        guard let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any], body["schemaVersion"] as? Int == 1, body["onay"] as? Bool == true, let code = body["kod"] as? String, (8...32).contains(Wire.normalizedCode(code).count) else { return .error(400, "Kayıt biçimi veya onay geçersiz.") }
        var index: Int?
        for (i, device) in state.devices.enumerated() where device.active && (device.expires ?? .distantPast) > Date() && !device.codeHash.isEmpty {
            if Crypto.equal(try Crypto.derive(code: code, salt: device.salt, count: 32), device.codeHash) { index = i; break }
        }
        guard let index else { return .error(403, "Kod geçersiz, kullanılmış veya süresi dolmuş.") }
        let device = state.devices[index], key = try Crypto.random(32), packet = try Crypto.seal(key: key, code: code)
        let oldKey = try? credentials.read("center:" + device.id)
        try credentials.write(key, "center:" + device.id)
        var next = state; next.devices[index].consent = Date(); next.devices[index].codeHash = Data(); next.devices[index].salt = Data(); next.devices[index].expires = nil
        do { try commit(next) }
        catch { if let oldKey { try? credentials.write(oldKey, "center:" + device.id) } else { credentials.remove("center:" + device.id) }; throw error }
        return ServerResponse(json: ["ok": true, "cihazId": device.id, "cihazAdi": device.name, "gonderimDakikasi": 5, "ayrintiDuzeyi": "ozet", "anahtar": packet])
    }
    private func summary(_ request: IncomingRequest, device: CenterDevice) throws -> ServerResponse {
        guard let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any], body["schemaVersion"] as? Int == 1, body["cihazId"] as? String == device.id, let day = body["clientTarih"] as? String, Storage.dateName(day), let totals = body["ozet"] as? [String: Any] else { return .error(400, "Özet şeması geçersiz.") }
        func integer(_ value: Any?, max limit: Int = 1440) -> Int { min(limit, max(0, (value as? NSNumber)?.intValue ?? 0)) }
        let sentText = body["gonderildiUtc"] as? String ?? ""
        let normalizedSent = sentText.replacingOccurrences(of: #"(\.\d{3})\d+Z$"#, with: "$1Z", options: .regularExpression)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let sent = formatter.date(from: normalizedSent) ?? ISO8601DateFormatter().date(from: normalizedSent) ?? formatter.date(from: sentText) ?? ISO8601DateFormatter().date(from: sentText), sent.timeIntervalSinceNow <= 900 else { return .error(400, "Gönderim zamanı geçersiz.") }
        let sequence = integer(body["sira"], max: Int(Int32.max))
        if let old = state.reports[day]?[device.id], old.received >= (device.consent ?? .distantPast), old.sequence > sequence || (old.sequence == sequence && old.sent >= sent) { return ServerResponse(json: ["ok": true, "eski": true]) }
        let apps: [CenterApp] = ((body["uygulamalar"] as? [[String: Any]]) ?? []).prefix(80).map {
            let category = $0["kategori"] as? String ?? "diger"
            return CenterApp(name: String(($0["ad"] as? String ?? "").prefix(100)), minutes: integer($0["dakika"]), category: ["calisma", "diger", "bosta", "belirsiz"].contains(category) ? category : "diger")
        }
        let health = body["health"] as? [String: Any] ?? [:], sync = health["senkron"] as? [String: Any] ?? [:]
        let report = CenterReport(deviceID: device.id, day: day, received: Date(), sent: sent, sequence: sequence, work: integer(totals["calismaDk"]), other: integer(totals["digerDk"]), idle: integer(totals["bostaDk"]), target: integer(totals["hedefDk"]), apps: apps, pendingRules: (sync["bekleyenKarar"] as? NSNumber).map { integer($0, max: 1000000) }, syncError: String((sync["hata"] as? String ?? "").prefix(720)))
        var next = state; next.reports[day, default: [:]][device.id] = report
        let cutoff = dayKey(Calendar.current.date(byAdding: .day, value: -90, to: Date())!)
        next.reports = next.reports.filter { $0.key >= cutoff }
        try commit(next); return ServerResponse(json: ["ok": true, "alindiUtc": iso(Date())])
    }
}

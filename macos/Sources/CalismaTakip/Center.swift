import Foundation
import Combine
import Network
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
    // Protokol v2. Eski center-state.json'da yoktur (nil).
    /// Koddan türetilen kayıt kanalı (k-<24 hex>)
    var channel: String?
    /// Kayıt kanalının posta kutusu jetonunun SHA-256 özeti
    var mailboxTokenHash: String?
    /// Kayıt tamamlandıktan sonra yanıt kutudan alınabilsin diye kanalın tanımlı kaldığı son an
    var mailboxUntil: Date?
    /// Kural yazma zarflarında tekrar koruması: kayan pencere
    var ruleWindowTop: Int64?
    var ruleWindowSeen: [Int64]?
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
struct CenterMailbox: Codable {
    var enabled = true
    var url: String
    var box: String
    var interval = 60
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
    /// Port yönlendirmeyle internetten erişilen adres (istemcilere şifreli yanıtla bildirilir)
    var internetURL: String?
    var mailbox: CenterMailbox?
}
/// v2 zarf işleminin sonucu: 200 ise `reply` yanıt zarfıdır, değilse düz hata.
struct EnvelopeResult {
    var status: Int
    var message: String
    var reply: [String: Any]?
    var authFailure = false
}
@MainActor final class Center: ObservableObject {
    @Published private(set) var state: CenterState
    @Published var status = "Merkez kapalı"
    @Published var mailboxStatus = ""
    private let storage: Storage
    private let credentials: CenterCredentials
    private let server = HTTPServer()
    private let mailboxClient = Client()
    private var attempts: [Date] = []
    private var addressFailures: [String: (start: Date, count: Int)] = [:]
    private var mailboxTimer: Timer?
    private var mailboxBusy = false
    private var mailboxLastRun = Date.distantPast
    private var mailboxListSignature = ""
    private var mailboxListSent = Date.distantPast
    private var tokenHashes: [String: String] = [:]
    private var cachedLocalAddress: String?
    private var cachedLocalAddressTime = Date.distantPast
    private static let ruleWindow: Int64 = 1024
    init(storage: Storage, credentials: CenterCredentials = CenterCredentials()) throws {
        self.credentials = credentials
        self.storage = storage; state = try storage.load("center-state.json", default: CenterState())
        guard state.version == 1 else { throw AppError.message("Merkez veri sürümü desteklenmiyor; dosya korundu.") }
        server.handler = { [weak self] in self?.handle($0) ?? .error(503, "Merkez hazır değil.") }
        server.statusChanged = { [weak self] in self?.status = $0 }
        if state.enabled { try server.start(port: state.port, lan: state.lan) }
        updateMailboxTimer()
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
        updateMailboxTimer()
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
        // v2: kodun kendisi değil, koddan türetilen kayıt anahtarı Anahtar Zinciri'nde tutulur
        let enrollment = try Zarf.enrollment(code: code)
        try credentials.write(enrollment.master, "center-enroll:" + device.id)
        device.channel = enrollment.channel
        device.mailboxTokenHash = Zarf.sha256Hex(Data(enrollment.keys.mailboxToken.utf8))
        device.mailboxUntil = nil
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

    // MARK: Adresler ve yerel ağ

    /// Yerel ağ ve VPN: loopback, 10/8, 172.16/12, 192.168/16, 169.254/16, 100.64/10, IPv6 ULA ve link-local
    /// (Windows: Test-DagitikYerelAdres). v1 uçları yalnızca bu adreslere açıktır.
    nonisolated static func isLocal(_ remote: String) -> Bool {
        var text = remote
        if let percent = text.firstIndex(of: "%") { text = String(text[..<percent]) }
        if text.lowercased().hasPrefix("::ffff:"), text.contains(".") { text = String(text.dropFirst(7)) }
        if let v4 = IPv4Address(text) {
            let b = [UInt8](v4.rawValue)
            guard b.count == 4 else { return false }
            if b[0] == 127 || b[0] == 10 { return true }
            if b[0] == 172 && (16...31).contains(b[1]) { return true }
            if b[0] == 192 && b[1] == 168 { return true }
            if b[0] == 169 && b[1] == 254 { return true }
            if b[0] == 100 && (64...127).contains(b[1]) { return true }
            return false
        }
        if let v6 = IPv6Address(text) {
            let b = [UInt8](v6.rawValue)
            guard b.count == 16 else { return false }
            if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return true }
            if b[0] == 0xFE && (b[1] & 0xC0) == 0x80 { return true }
            if (b[0] & 0xFE) == 0xFC { return true }
        }
        return false
    }
    private func localURL() -> String {
        guard state.lan else { return "http://127.0.0.1:\(state.port)" }
        // Host.current() ad çözümlemesi yapabilir; her yanıtta değil 5 dakikada bir sorulur
        if cachedLocalAddress == nil || Date().timeIntervalSince(cachedLocalAddressTime) > 300 {
            cachedLocalAddress = Host.current().addresses.first { !$0.contains(":") && Center.isLocal($0) && !$0.hasPrefix("127.") } ?? "127.0.0.1"
            cachedLocalAddressTime = Date()
        }
        return "http://\(cachedLocalAddress ?? "127.0.0.1"):\(state.port)"
    }
    /// İstemcilere şifreli yanıtla bildirilen güncel adresler.
    func addresses() -> [String: Any] {
        var extra: [String] = []
        if let text = state.internetURL, let address = CenterAddress.parse(text), address.kind == .direct { extra.append(address.text) }
        var mailbox = ""
        if let box = state.mailbox, box.enabled, let address = CenterAddress.parse(box.url), address.kind == .direct { mailbox = address.root + "/k/" + box.box }
        return ["sunucuUrl": localURL(), "ekAdresler": extra, "postaUrl": mailbox]
    }
    func setInternetURL(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = state
        if trimmed.isEmpty { next.internetURL = nil }
        else {
            guard let address = CenterAddress.parse(trimmed), address.kind == .direct else { throw AppError.message("İnternet adresi http://alanadi:port biçiminde olmalı.") }
            next.internetURL = address.text
        }
        try commit(next)
    }

    // MARK: Yönlendirme

    private func route(_ request: IncomingRequest) throws -> ServerResponse {
        let path = request.target.components(separatedBy: "?")[0]
        if path == "/health", request.method == "GET" { return ServerResponse(json: ["ok": true, "zamanUtc": iso(Date()), "protokol": 2]) }
        if path == "/v2/zarf", request.method == "POST" { return try envelopeRequest(request) }
        // v1 imzalı ama şifresizdir ve v1 kaydında kod düz gider: internete açılmaz.
        guard Center.isLocal(request.remote) else { return .error(403, "Bu uç yalnızca yerel ağdan kullanılabilir; Aizen istemcisini güncelleyin.") }
        if path == "/v1/kayit", request.method == "POST" { return try enroll(request) }
        guard let id = request.headers["x-ct-cihaz"], let device = state.devices.first(where: { $0.id == id && $0.active && $0.consent != nil }), let timestamp = request.headers["x-ct-zaman"], let time = TimeInterval(timestamp), abs(Date().timeIntervalSince1970 - time) <= 900, let given = request.headers["x-ct-imza"], given.count == 64, let key = try? credentials.read("center:" + id) else { return .error(401, "Cihaz veya zaman damgası geçersiz.") }
        let signed = request.method == "GET" ? Data(request.target.utf8) : request.body
        let expected = Crypto.signature(key: key, timestamp: timestamp, body: signed)
        guard Crypto.equal(Data(given.lowercased().utf8), Data(expected.utf8)) else { return .error(401, "İmza geçersiz.") }
        switch (request.method, path) {
        case ("GET", "/v1/kurallar"): return try rulesResponse()
        case ("POST", "/v1/kural"): return try writeRules(request.body, device: device)
        case ("GET", "/v1/toplam"):
            let day = URLComponents(string: "http://localhost" + request.target)?.queryItems?.first(where: { $0.name == "tarih" })?.value ?? dayKey(Date())
            guard Storage.dateName(day) else { return .error(400, "Tarih geçersiz.") }
            return totalResponse(day: day, id: id)
        case ("POST", "/v1/ozet"): return try summary(request.body, device: device)
        default: return .error(404, "Uç nokta bulunamadı.")
        }
    }
    private func rulesResponse() throws -> ServerResponse {
        let rules = SharedRules(rules: state.rules, deleted: state.deleted)
        var json = try JSONSerialization.jsonObject(with: storage.encoder.encode(rules)) as! [String: Any]
        json["sonDegisiklikUtc"] = state.ruleVersion; json["kuralSayisi"] = state.rules.rows.count
        return ServerResponse(json: json)
    }
    private func writeRules(_ requestBody: Data, device: CenterDevice) throws -> ServerResponse {
        guard device.canWriteRules else { return .error(403, "Bu cihazın kural yazma izni yok.") }
        guard let body = try? JSONSerialization.jsonObject(with: requestBody) as? [String: Any], body["schemaVersion"] as? Int == 1, let decisions = body["kararlar"] as? [[String: Any]], decisions.count <= 200 else { return .error(400, "Kural şeması geçersiz.") }
        var next = state; var count = 0; var invalid = 0
        for raw in decisions {
            guard let value = raw["oge"] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 160, let kind = RuleKind(rawValue: raw["tur"] as? String ?? ""), let decision = Decision(rawValue: raw["karar"] as? String ?? "") else { invalid += 1; continue }
            let change = RuleChange(value: value, kind: kind, decision: decision)
            next.rules.apply(change); next.deleted.removeAll { equivalent($0.oge, value) && $0.tur == kind }; count += 1
        }
        if count > 0 { next.ruleVersion = nextRuleVersion(); try commit(next) }
        return ServerResponse(json: ["ok": true, "islenen": count, "hatali": invalid, "sonDegisiklikUtc": state.ruleVersion])
    }
    private func totalResponse(day: String, id: String) -> ServerResponse {
        let reports = state.reports[day] ?? [:], sum = total(day: day), own = reports[id]?.work ?? 0
        let others: [[String: Any]] = reports.values.filter { $0.deviceID != id }.map { report in ["cihazId": report.deviceID, "ad": state.devices.first(where: { $0.id == report.deviceID })?.name ?? report.deviceID, "calismaDk": report.work] }
        return ServerResponse(json: ["ok": true, "tarih": day, "toplamDk": sum, "buCihazDk": own, "digerCihazDk": sum-own, "cihazSayisi": reports.count, "cihazlar": others])
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
        // Kod iki protokolde birden tükenir
        next.devices[index].channel = nil; next.devices[index].mailboxTokenHash = nil; next.devices[index].mailboxUntil = nil
        next.devices[index].ruleWindowTop = nil; next.devices[index].ruleWindowSeen = nil
        do { try commit(next) }
        catch { if let oldKey { try? credentials.write(oldKey, "center:" + device.id) } else { credentials.remove("center:" + device.id) }; throw error }
        credentials.remove("center-enroll:" + device.id)
        return ServerResponse(json: ["ok": true, "cihazId": device.id, "cihazAdi": device.name, "gonderimDakikasi": 5, "ayrintiDuzeyi": "ozet", "anahtar": packet])
    }
    private func summary(_ requestBody: Data, device: CenterDevice) throws -> ServerResponse {
        guard let body = try? JSONSerialization.jsonObject(with: requestBody) as? [String: Any], body["schemaVersion"] as? Int == 1, body["cihazId"] as? String == device.id, let day = body["clientTarih"] as? String, Storage.dateName(day), let totals = body["ozet"] as? [String: Any] else { return .error(400, "Özet şeması geçersiz.") }
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

    // MARK: Protokol v2 (uyumluluk/PROTOKOL-V2.md)

    private func envelopeRequest(_ request: IncomingRequest) throws -> ServerResponse {
        let now = Date()
        if let failures = addressFailures[request.remote], now.timeIntervalSince(failures.start) <= 600, failures.count >= 30 {
            return .error(429, "Çok fazla hatalı deneme. 10 dakika sonra tekrar deneyin.")
        }
        var result = EnvelopeResult(status: 400, message: "Zarf okunamadı.", reply: nil, authFailure: true)
        if let envelope = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] { result = try process(envelope: envelope) }
        if result.authFailure {
            if addressFailures.count > 2000 { addressFailures = addressFailures.filter { now.timeIntervalSince($0.value.start) <= 600 } }
            if let failures = addressFailures[request.remote], now.timeIntervalSince(failures.start) <= 600 {
                addressFailures[request.remote] = (failures.start, failures.count + 1)
            } else { addressFailures[request.remote] = (now, 1) }
        }
        if let reply = result.reply { return ServerResponse(status: 200, json: reply) }
        return .error(result.status, result.message)
    }
    /// Doğrudan bağlantı ve posta kutusu aynı yoldan işlenir.
    func process(envelope: [String: Any]) throws -> EnvelopeResult {
        guard Zarf.isValid(envelope), envelope["yon"] as? String == "istek",
              let device = envelope["cihaz"] as? String, let kind = envelope["tur"] as? String,
              let sequence = (envelope["sayac"] as? NSNumber)?.int64Value, let time = (envelope["zaman"] as? NSNumber)?.int64Value else {
            return EnvelopeResult(status: 400, message: "Zarf biçimi geçersiz.", reply: nil, authFailure: true)
        }
        let now = Int64(Date().timeIntervalSince1970)
        // Posta kutusunda bekleyen zarf günlerce eski olabilir: üst sınır 30 gün; gelecek en çok 15 dk
        guard time <= now + 900, time >= now - 30 * 86400 else { return EnvelopeResult(status: 401, message: "Zarf zamanı geçersiz.", reply: nil, authFailure: true) }
        if Zarf.isChannel(device) { return try enrollV2(envelope: envelope, channel: device, kind: kind, sequence: sequence) }
        guard let index = state.devices.firstIndex(where: { $0.id == device && $0.active && $0.consent != nil }),
              let key = try? credentials.read("center:" + device) else { return EnvelopeResult(status: 401, message: "Kimlik doğrulanamadı.", reply: nil, authFailure: true) }
        let keys = Zarf.keys(deviceKey: key)
        guard let plain = try? Zarf.open(envelope, keys: keys) else { return EnvelopeResult(status: 401, message: "Kimlik doğrulanamadı.", reply: nil, authFailure: true) }
        if kind == "kural" {
            guard try acceptRuleSequence(index: index, sequence: sequence) else { return EnvelopeResult(status: 409, message: "Bu zarf daha önce işlendi.", reply: nil) }
        }
        let record = state.devices[index]
        let response: ServerResponse
        switch kind {
        case "ozet": response = try summary(plain, device: record)
        case "kural": response = try writeRules(plain, device: record)
        case "kurallar": response = try rulesResponse()
        case "toplam":
            var day = dayKey(Date())
            if let object = try? JSONSerialization.jsonObject(with: plain) as? [String: Any], let requested = object["tarih"] as? String, Storage.dateName(requested) { day = requested }
            response = totalResponse(day: day, id: device)
        default: response = .error(404, "Bilinmeyen işlem.")
        }
        // Güncel adresler her yanıtta şifreli gider: sonradan eklenen posta kutusu yeniden eşleşmeden öğrenilir
        let content: [String: Any] = ["kod": response.status, "govde": response.json, "adresler": addresses()]
        let data = try JSONSerialization.data(withJSONObject: content, options: [.sortedKeys, .withoutEscapingSlashes])
        let reply = try Zarf.seal(data, keys: keys, device: device, kind: kind, direction: "yanit", sequence: sequence)
        return EnvelopeResult(status: 200, message: "", reply: reply)
    }
    private func acceptRuleSequence(index: Int, sequence: Int64) throws -> Bool {
        guard sequence > 0 else { return false }
        var next = state
        var top = next.devices[index].ruleWindowTop ?? 0
        var seen = next.devices[index].ruleWindowSeen ?? []
        if sequence <= top - Center.ruleWindow || seen.contains(sequence) { return false }
        top = max(top, sequence)
        seen.append(sequence)
        seen = seen.filter { $0 > top - Center.ruleWindow }.sorted()
        next.devices[index].ruleWindowTop = top
        next.devices[index].ruleWindowSeen = seen
        try commit(next)
        return true
    }
    private func sealEnrollmentReply(_ status: Int, _ body: [String: Any], enrollment: Zarf.Enrollment, sequence: Int64) throws -> EnvelopeResult {
        let content: [String: Any] = ["kod": status, "govde": body]
        let data = try JSONSerialization.data(withJSONObject: content, options: [.sortedKeys, .withoutEscapingSlashes])
        let reply = try Zarf.seal(data, keys: enrollment.keys, device: enrollment.channel, kind: "kayit", direction: "yanit", sequence: sequence)
        return EnvelopeResult(status: 200, message: "", reply: reply)
    }
    private func enrollV2(envelope: [String: Any], channel: String, kind: String, sequence: Int64) throws -> EnvelopeResult {
        let rejected = EnvelopeResult(status: 403, message: "Kod geçersiz, kullanılmış veya süresi dolmuş.", reply: nil, authFailure: true)
        guard kind == "kayit" else { return EnvelopeResult(status: 400, message: "Zarf türü geçersiz.", reply: nil, authFailure: true) }
        guard let index = state.devices.firstIndex(where: { $0.channel == channel && $0.active && !$0.codeHash.isEmpty && ($0.expires ?? .distantPast) > Date() }),
              let master = try? credentials.read("center-enroll:" + state.devices[index].id) else { return rejected }
        let enrollment = Zarf.enrollment(master: master)
        guard enrollment.channel == channel, let plain = try? Zarf.open(envelope, keys: enrollment.keys),
              let body = try? JSONSerialization.jsonObject(with: plain) as? [String: Any] else { return rejected }
        guard body["schemaVersion"] as? Int == 2, body["onay"] as? Bool == true else {
            return try sealEnrollmentReply(400, ["ok": false, "hata": "Kullanıcı onayı olmadan kayıt yapılmaz."], enrollment: enrollment, sequence: sequence)
        }
        let device = state.devices[index], key = try Crypto.random(32)
        let oldKey = try? credentials.read("center:" + device.id)
        try credentials.write(key, "center:" + device.id)
        var next = state
        next.devices[index].consent = Date(); next.devices[index].codeHash = Data(); next.devices[index].salt = Data(); next.devices[index].expires = nil
        next.devices[index].mailboxUntil = Date().addingTimeInterval(1800)
        next.devices[index].ruleWindowTop = nil; next.devices[index].ruleWindowSeen = nil
        do { try commit(next) }
        catch { if let oldKey { try? credentials.write(oldKey, "center:" + device.id) } else { credentials.remove("center:" + device.id) }; throw error }
        credentials.remove("center-enroll:" + device.id)
        var reply: [String: Any] = ["ok": true, "cihazId": device.id, "cihazAdi": device.name, "anahtar": key.base64EncodedString(), "gonderimDakikasi": 5, "ayrintiDuzeyi": "ozet"]
        for (name, value) in addresses() { reply[name] = value }
        return try sealEnrollmentReply(200, reply, enrollment: enrollment, sequence: sequence)
    }

    // MARK: Posta kutusu

    private func updateMailboxTimer() {
        let wanted = state.enabled && state.mailbox?.enabled == true
        if wanted && mailboxTimer == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in await self?.pollMailbox(force: false) } }
            RunLoop.main.add(timer, forMode: .common); mailboxTimer = timer
        } else if !wanted {
            mailboxTimer?.invalidate(); mailboxTimer = nil
        }
    }
    func connectMailbox(url: String, adminToken: String, interval: Int = 60) async throws -> String {
        guard let address = CenterAddress.parse(url), address.kind == .direct, address.isSecureTransport else { throw AppError.message("Posta kutusu adresi https://sunucu biçiminde olmalı (yol eklemeyin).") }
        let admin = adminToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard admin.range(of: #"^[A-Za-z0-9_-]{32,128}$"#, options: .regularExpression) != nil else { throw AppError.message("Yönetim jetonu biçimi geçersiz.") }
        // Aynı sunucuya yeniden bağlanırken kutu korunur: istemcilerdeki adres değişmez
        var box = ""
        if let current = state.mailbox, current.url == address.root { box = current.box }
        if box.range(of: #"^[0-9a-f]{16,64}$"#, options: .regularExpression) == nil { box = Zarf.hex(try Crypto.random(16)) }
        let token = Zarf.hex(try Crypto.random(32))
        let body = try JSONSerialization.data(withJSONObject: ["kutu": box, "merkezJetonOzeti": Zarf.sha256Hex(Data(token.utf8))], options: [.sortedKeys])
        do { _ = try await mailboxClient.send(address.root + "/r1/kutu", body: body, headers: ["X-Aizen-Yonetim": admin]) }
        catch let failure as HTTPFailure where failure.status == 401 { throw AppError.message("Posta kutusu yönetim jetonunu kabul etmedi.") }
        try credentials.write(Data(token.utf8), "center-mailbox")
        var next = state
        next.mailbox = CenterMailbox(enabled: true, url: address.root, box: box, interval: max(2, min(3600, interval)))
        try commit(next)
        mailboxListSignature = ""
        updateMailboxTimer()
        return address.root + "/k/" + box
    }
    func disconnectMailbox() throws {
        var next = state
        next.mailbox?.enabled = false
        try commit(next)
        credentials.remove("center-mailbox")
        updateMailboxTimer()
        mailboxStatus = ""
    }
    private func mailboxDeviceList() -> [[String: Any]] {
        var list: [[String: Any]] = []
        let now = Date()
        for device in state.devices {
            if device.active, let consent = device.consent {
                let cacheKey = device.id + "|" + String(consent.timeIntervalSince1970)
                if tokenHashes[cacheKey] == nil, let key = try? credentials.read("center:" + device.id) {
                    tokenHashes[cacheKey] = Zarf.sha256Hex(Data(Zarf.keys(deviceKey: key).mailboxToken.utf8))
                }
                if let hash = tokenHashes[cacheKey] { list.append(["cihaz": device.id, "jetonOzeti": hash, "bitis": 0]) }
            }
            if let channel = device.channel, let hash = device.mailboxTokenHash {
                let until = device.codeHash.isEmpty ? device.mailboxUntil : device.expires
                if let until, until > now { list.append(["cihaz": channel, "jetonOzeti": hash, "bitis": Int64(until.timeIntervalSince1970)]) }
            }
        }
        return list
    }
    /// Kutudaki zarfları alır, işler, yanıtları bırakır. Hata yerel merkezi durdurmaz.
    func pollMailbox(force: Bool) async {
        guard let mailbox = state.mailbox, mailbox.enabled, state.enabled, !mailboxBusy else { return }
        var interval = TimeInterval(max(2, min(3600, mailbox.interval)))
        // Kayıt bekleyen kod varken kullanıcı ekranda bekliyordur: sık bak
        if interval > 5, state.devices.contains(where: { $0.channel != nil && !$0.codeHash.isEmpty && ($0.expires ?? .distantPast) > Date() }) { interval = 5 }
        guard force || Date().timeIntervalSince(mailboxLastRun) >= interval else { return }
        mailboxBusy = true
        mailboxLastRun = Date()
        defer { mailboxBusy = false }
        do {
            guard let address = CenterAddress.parse(mailbox.url), address.kind == .direct, address.isSecureTransport else { throw AppError.message("Posta kutusu adresi geçersiz.") }
            let token = String(decoding: try credentials.read("center-mailbox"), as: UTF8.self)
            let headers = ["X-Aizen-Kutu": mailbox.box, "X-Aizen-Jeton": token]
            let listData = try JSONSerialization.data(withJSONObject: ["cihazlar": mailboxDeviceList()], options: [.sortedKeys])
            let signature = Zarf.sha256Hex(listData)
            if signature != mailboxListSignature || Date().timeIntervalSince(mailboxListSent) > 1800 {
                _ = try await mailboxClient.send(address.root + "/r1/merkez/cihazlar", body: listData, headers: headers)
                mailboxListSignature = signature
                mailboxListSent = Date()
            }
            var processed = 0
            for _ in 0..<20 {
                let data = try await mailboxClient.send(address.root + "/r1/merkez/gelen?en=25", method: "GET", body: nil, headers: headers, timeout: 30)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let messages = object["mesajlar"] as? [[String: Any]], !messages.isEmpty else { break }
                var replies: [[String: Any]] = []
                var numbers: [Int64] = []
                for message in messages {
                    if let number = (message["no"] as? NSNumber)?.int64Value { numbers.append(number) }
                    guard let envelope = message["zarf"] as? [String: Any], let device = message["cihaz"] as? String,
                          envelope["cihaz"] as? String == device, let result = try? process(envelope: envelope), let reply = result.reply else { continue }
                    let kind = envelope["tur"] as? String ?? ""
                    // Kutuda aynı anahtarlı eski yanıt yenisiyle değişir
                    let coalesce = ["kurallar", "toplam", "ozet"].contains(kind) ? kind : ""
                    replies.append(["cihaz": device, "anahtar": coalesce, "zarf": reply])
                }
                if !replies.isEmpty {
                    let replyData = try JSONSerialization.data(withJSONObject: ["mesajlar": replies])
                    _ = try await mailboxClient.send(address.root + "/r1/merkez/gonder", body: replyData, headers: headers, timeout: 30)
                }
                let ackData = try JSONSerialization.data(withJSONObject: ["nolar": numbers])
                _ = try await mailboxClient.send(address.root + "/r1/merkez/onay", body: ackData, headers: headers)
                processed += messages.count
                if messages.count < 25 { break }
            }
            mailboxStatus = "Posta kutusu bağlı · son yoklama " + Date().formatted(date: .omitted, time: .shortened) + (processed > 0 ? " · \(processed) zarf işlendi" : "")
        } catch {
            // Liste gönderilemediyse sonraki turda yeniden gönderilsin
            mailboxListSignature = ""
            mailboxStatus = "Posta kutusuna ulaşılamadı; merkez yerel olarak çalışmaya devam ediyor."
        }
    }
}

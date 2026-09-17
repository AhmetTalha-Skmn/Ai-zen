import SwiftUI
import AppKit
import ServiceManagement
import TakipCore

@MainActor final class Engine: ObservableObject {
    @Published private(set) var state: TrackerState
    @Published var error = ""
    @Published var information = ""
    @Published var currentApp = "Henüz ölçüm yok"
    @Published var busy = false
    @Published var permissionsOK = Activity.permission
    let storage: Storage
    let center: Center
    private let client = Client()
    private let warnings = Warnings()
    private var timer: Timer?
    private var previous: Sample?
    private var lastSync = Date.distantPast
    private var sessionStart = Date()
    private var lastWarning = Date.distantPast
    private var lastWorkSeen = Date.distantPast
    private var lastBackupAttempt = Date.distantPast
    init() throws {
        // state @Published sarmalayıcıdır; tüm alanlar atanmadan okunamaz. Yerel değişkende doğrula.
        let storage = try Storage()
        let loaded = try storage.load("state.json", default: TrackerState())
        guard loaded.version == 1 else { throw AppError.message("Veri sürümü desteklenmiyor; mevcut dosya korundu.") }
        self.storage = storage
        state = loaded
        center = try Center(storage: storage)
        // A restored/sleeping app does not count time before its first measurement.
        let samplingTimer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        RunLoop.main.add(samplingTimer, forMode: .common); timer = samplingTimer
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.previous = nil; self?.warnings.dismiss() } }
        tick()
    }
    var today: Day { state.days[dayKey(Date())] ?? Day(date: dayKey(Date())) }
    var otherMinutes: Int { state.connection == nil ? 0 : state.sharedTotal?.usableMinutes(now: Date()) ?? 0 }
    var total: Int { today.minutes + otherMinutes }
    var paused: Bool { state.settings.isPaused(at: Date()) }
    var stopped: Bool { FileManager.default.fileExists(atPath: storage.stopFile.path) }
    var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func mutate(_ operation: (inout TrackerState) throws -> Void) throws {
        var next = state; try operation(&next); try storage.save(next, name: "state.json"); state = next
    }
    func action(_ operation: () throws -> Void) { do { try operation(); error = "" } catch { self.error = error.localizedDescription } }
    func target(_ minutes: Int) { action { guard (1...1440).contains(minutes) else { throw AppError.message("Hedef 1–1440 dakika olmalı.") }; try mutate { $0.settings.targetMinutes = minutes } } }
    func pause(minutes: Int?) {
        action { try mutate { $0.settings.paused = minutes == nil; $0.settings.pauseUntil = minutes.map { Date().addingTimeInterval(Double($0 * 60)) } } }
        previous = nil; warnings.dismiss()
    }
    func resume() { action { try mutate { $0.settings.paused = false; $0.settings.pauseUntil = nil } }; previous = nil }
    func focus(minutes: Int) {
        // Ekran kilidi kapalıyken odak oturumu engel göstermez; başlatmanın anlamı yok (Windows'ta periyot da kapalı).
        if minutes > 0, !state.settings.screenLockEnabled { information = "Ekran kilidi kapalı; odak oturumu engel göstermez. Ayarlar’dan açabilirsin."; return }
        action { try mutate { $0.settings.focusUntil = minutes > 0 ? Date().addingTimeInterval(Double(minutes * 60)) : nil } }
        if minutes == 0 { warnings.dismiss() }
    }
    func setInstallType(_ type: InstallType) {
        // Tür değişince özellikler o türün varsayılanına döner.
        action { try mutate { $0.settings.installType = type.rawValue; $0.settings.reminders = nil; $0.settings.screenLock = nil; if !type.defaultScreenLock { $0.settings.focusUntil = nil } } }
        warnings.dismiss()
    }
    func setReminders(_ enabled: Bool) { action { try mutate { $0.settings.reminders = enabled } }; if !enabled { warnings.dismiss() } }
    func setScreenLock(_ enabled: Bool) {
        action { try mutate { $0.settings.screenLock = enabled; if !enabled { $0.settings.focusUntil = nil } } }
        warnings.dismiss()
    }
    func resetFeatures() { action { try mutate { $0.settings.reminders = nil; $0.settings.screenLock = nil } }; warnings.dismiss() }
    func emergency() {
        action {
            if stopped { try FileManager.default.removeItem(at: storage.stopFile) }
            else { try Data("Engeller kapalı".utf8).write(to: storage.stopFile, options: .atomic) }
        }
        warnings.dismiss(); objectWillChange.send()
    }
    func login(_ enabled: Bool) {
        action { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        objectWillChange.send()
    }
    func decide(value: String, kind: RuleKind, decision: Decision) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        action {
            guard !value.isEmpty, value.count <= 160 else { throw AppError.message("Kural 1–160 karakter olmalı.") }
            let change = RuleChange(value: value, kind: kind, decision: decision)
            try mutate { next in
                next.rules.apply(change)
                if next.connection != nil {
                    next.pending.removeAll { equivalent($0.oge, value) && $0.tur == kind }
                    next.pending.append(change)
                    if next.pending.count > 200 { next.pending = Array(next.pending.suffix(200)) }
                }
            }
        }
    }
    func removeRule(_ change: RuleChange) {
        action { try mutate { next in next.rules.remove(change); next.pending.removeAll { equivalent($0.oge, change.oge) && $0.tur == change.tur } } }
        information = "Yerel kural kaldırıldı. Merkezde varsa sonraki senkronda tekrar gelir; ortak silme merkez panelinden yapılır."
    }
    func connect(server: String, code: String, name: String, consent: Bool) async {
        guard consent, !busy else { return }; busy = true; defer { busy = false }
        do {
            guard state.connection == nil else { throw AppError.message("Önce mevcut merkez bağlantısını kesin.") }
            let connection = try await client.enroll(server: server, code: code, name: name)
            try mutate { $0.connection = connection; $0.sharedTotal = nil; $0.dirtyDays = Array($0.days.keys) }
            information = "Merkeze bağlandı. Anahtar Anahtar Zinciri’nde saklanıyor."; error = ""; lastSync = .distantPast
        } catch { self.error = error.localizedDescription }
    }
    func disconnect() {
        guard !busy else { return }
        action {
            let id = state.connection?.deviceID
            try mutate { $0.connection = nil; $0.sharedTotal = nil; $0.pending = [] }
            if let id { Secrets.delete("client:" + id) }
        }
    }
    func tick() {
        let now = Date(); permissionsOK = Activity.permission; warnings.expire(now: now)
        if paused || stopped { warnings.dismiss() }
        // Tam ekran uyarı açıkken ölçüm durur; ekran kilidi kapalıyken çıkan küçük pencere ölçümü durdurmaz.
        if !paused, !warnings.blocksSampling, let sample = Activity.sample() {
            currentApp = sample.app + (sample.domain.isEmpty ? "" : " · " + sample.domain)
            let elapsed = Classifier.elapsed(previous: previous?.time, now: sample.time)
            if var prior = previous, elapsed > 0 {
                // Attribute the observed interval to its preceding foreground sample; split at midnight.
                var cursor = prior.time
                while cursor < sample.time {
                    let midnight = Calendar.current.dateInterval(of: .day, for: cursor)!.end
                    let end = min(midnight, sample.time), amount = end.timeIntervalSince(cursor)
                    prior.time = cursor
                    let result = Classifier.classify(prior, rules: state.rules)
                    do {
                        try mutate { next in
                            let key = dayKey(cursor); var day = next.days[key] ?? Day(date: key)
                            day.add(prior, seconds: amount, classification: result); next.days[key] = day
                            if !next.dirtyDays.contains(key) { next.dirtyDays.append(key) }
                        }
                        try storage.append(prior, seconds: amount, category: result.category)
                    } catch { self.error = error.localizedDescription }
                    cursor = end
                }
            }
            previous = sample
            let classification = Classifier.classify(sample, rules: state.rules)
            // Windows izleyicisi gibi: sayılan her süre çalışmadır ("belirsiz sayılsın" açıkken belirsiz
            // de). Nötr kurallarla her uygulama belirsiz olduğundan yalnız .work'e bakmak yetmez.
            let isWorking = classification.counted
            // Çalışma anı yalnız bellekte ilerler; her 10 sn state.json yeniden yazılmaz.
            if isWorking { lastWorkSeen = now }
            if !stopped, !warnings.visible, now.timeIntervalSince(lastWarning) > 180 {
                let settings = state.settings
                // Engel yalnız ekran kilidi açıkken; hatırlatma yalnız hatırlatmalar açıkken (şirket türünde hiç yok).
                let blocking = settings.screenLockEnabled && classification.mayBlock && (settings.focusUntil ?? .distantPast) > now
                let reminderBase = max(settings.lastReminder ?? sessionStart, lastWorkSeen)
                let reminder = settings.remindersEnabled && !isWorking && total < settings.targetMinutes && now.timeIntervalSince(reminderBase) >= 2700
                if blocking || reminder {
                    lastWarning = now
                    action { try mutate { $0.settings.lastReminder = now } }
                    warnings.show(message: blocking ? "Odak oturumundasın: \(sample.app) çalışma olarak sayılmıyor." : "Günlük hedefin için çalışmaya dön.", total: total, target: settings.targetMinutes,
                        fullScreen: settings.screenLockEnabled,
                        onPause: { [weak self] in self?.pause(minutes: 5) }, onStop: { [weak self] in self?.emergency() })
                }
            }
        } else { previous = nil }
        if now.timeIntervalSince(lastSync) >= 300, state.connection != nil, !busy {
            lastSync = now; Task { await sync() }
        }
        if !busy, !state.days.isEmpty, now.timeIntervalSince(lastBackupAttempt) >= 3600, now.timeIntervalSince(state.settings.lastBackup ?? .distantPast) > 7 * 86400 {
            lastBackupAttempt = now
            action {
                _ = try storage.backup(state)
                try mutate { $0.settings.lastBackup = now }
                try storage.retain(days: state.settings.retentionDays, now: now)
                let cutoff = dayKey(Calendar.current.date(byAdding: .day, value: -state.settings.retentionDays, to: now)!)
                try mutate { $0.days = $0.days.filter { $0.key >= cutoff }; $0.dirtyDays.removeAll { $0 < cutoff } }
            }
        }
    }
    func sync() async {
        guard let connection = state.connection, !busy else { return }
        if (connection.protocolVersion ?? 1) >= 2 { await syncV2() } else { await syncV1() }
    }
    /// Protokol v2 (uyumluluk/PROTOKOL-V2.md §7): önce doğrudan adresler, ulaşılamazsa posta kutusu.
    private func syncV2() async {
        guard var connection = state.connection, !busy else { return }
        busy = true; defer { busy = false }
        var failures: [String] = []
        let keys: ZarfKeys
        do { keys = Zarf.keys(deviceKey: try Secrets.get("client:" + connection.deviceID)) }
        catch {
            connection.lastError = error.localizedDescription
            let snapshot = connection
            action { try mutate { $0.connection = snapshot } }
            return
        }
        var root: String?
        for candidate in connection.directAddresses ?? [] where root == nil {
            if await client.isV2Center(candidate) { root = candidate }
        }
        var mailbox: CenterAddress?
        if let text = connection.mailbox, let address = CenterAddress.parse(text), address.kind == .mailbox, address.isSecureTransport { mailbox = address }
        var directWorked = false
        if let root {
            do {
                failures = try await directRound(root: root, keys: keys, connection: &connection)
                connection.lastChannel = "dogrudan"
                directWorked = true
                if let mailbox, connection.mailboxAwaiting == true {
                    var ignored: [String] = []
                    try? await mailboxReplies(mailbox, keys: keys, connection: &connection, failures: &ignored)
                }
            } catch { failures = ["Doğrudan bağlantı: " + safeNetworkError(error)] }
        }
        if !directWorked {
            if let mailbox {
                do {
                    failures = try await mailboxRound(mailbox, keys: keys, connection: &connection)
                    connection.lastChannel = "posta"
                } catch { failures.append("Posta kutusu: " + safeNetworkError(error)) }
            } else if root == nil {
                failures.append("Merkeze ulaşılamadı: doğrudan adres yanıt vermedi, posta kutusu tanımlı değil.")
            }
        }
        connection.lastError = failures.joined(separator: " | ")
        let snapshot = connection
        action { try mutate { $0.connection = snapshot } }
    }
    /// Sayaç zarf gönderilmeden kaydedilir: çökme sonrası aynı sayaç yeniden kullanılmaz.
    private func nextCounter(_ connection: inout Connection) throws -> Int64 {
        let next = (connection.counter ?? 0) + 1
        connection.counter = next
        let snapshot = connection
        try mutate { $0.connection = snapshot }
        return next
    }
    private func applyAddresses(_ reported: [String: Any]?, used: String?, connection: inout Connection) {
        let merged = CenterAddress.merge(reported: reported, direct: connection.directAddresses ?? [], mailbox: connection.mailbox, used: used)
        connection.directAddresses = merged.direct
        connection.mailbox = merged.mailbox
    }
    private func applyRules(_ reply: EnvelopeReply, connection: inout Connection, failures: inout [String]) throws {
        guard reply.status == 200, reply.body["ok"] as? Bool == true else { failures.append("Kural alımı: merkez HTTP \(reply.status) döndürdü."); return }
        let data = try JSONSerialization.data(withJSONObject: reply.body)
        let rules = try storage.decoder.decode(SharedRules.self, from: data)
        try mutate { next in
            next.rules.merge(rules)
            for change in next.pending { next.rules.apply(change) }
        }
        connection.lastRuleSuccess = Date()
    }
    private func applyTotal(_ reply: EnvelopeReply, day: String, failures: inout [String]) throws {
        guard reply.status == 200, reply.body["ok"] as? Bool == true, reply.body["tarih"] as? String == day,
              let minutes = reply.body["digerCihazDk"] as? Int else { failures.append("Ortak sayaç: yanıt geçersiz."); return }
        // Posta kutusunda bekleyen yanıt bayat toplamı taze göstermesin: merkezin yanıt zamanı esas alınır
        let produced = Date(timeIntervalSince1970: TimeInterval(reply.time))
        let updated = min(Date(), produced)
        try mutate { $0.sharedTotal = SharedTotal(date: day, otherMinutes: minutes, updated: updated) }
    }
    /// Ağ ya da doğrulama hatası fırlatılır (çağıran posta kutusuna geçer); merkezin reddi başarısızlık listesine yazılır.
    private func directRound(root: String, keys: ZarfKeys, connection: inout Connection) async throws -> [String] {
        var failures: [String] = []
        let days = Array(Set(state.dirtyDays + [dayKey(Date())])).sorted().prefix(30)
        for key in days {
            guard let day = state.days[key] else { continue }
            connection.sequence += 1
            let counter = try nextCounter(&connection)
            let body = try Wire.json(Wire.body(day: day, connection: connection, target: state.settings.targetMinutes, pending: state.pending.count, now: Date()))
            let reply = try await client.direct(root: root, keys: keys, device: connection.deviceID, kind: "ozet", sequence: counter, plain: body)
            applyAddresses(reply.addresses, used: root, connection: &connection)
            guard reply.status == 200, reply.body["ok"] as? Bool == true else { failures.append("Özet: merkez HTTP \(reply.status) döndürdü."); break }
            connection.lastSuccess = Date()
            let snapshot = connection
            try mutate { next in
                // Ağ isteği sırasında yeni ölçüm almış gün kuyruktan düşmesin.
                if next.days[key]?.lastSample == day.lastSample { next.dirtyDays.removeAll { $0 == key } }
                next.connection = snapshot
            }
        }
        let sent = state.pending
        if !sent.isEmpty {
            let decisions = sent.map { ["oge": $0.oge, "tur": $0.tur.rawValue, "karar": $0.karar.rawValue] }
            let body = try Wire.json(["schemaVersion": 1, "cihazId": connection.deviceID, "kararlar": decisions])
            let counter = try nextCounter(&connection)
            let reply = try await client.direct(root: root, keys: keys, device: connection.deviceID, kind: "kural", sequence: counter, plain: body)
            if reply.status == 200, reply.body["ok"] as? Bool == true, reply.body["hatali"] as? Int == 0 {
                let ids = Set(sent.map(\.id)); try mutate { $0.pending.removeAll { ids.contains($0.id) } }
            } else if reply.status == 403 {
                try mutate { $0.pending.removeAll() }
                information = "Merkezde kural yazma yetkisi yok; bekleyen kararlar temizlendi."
            } else { failures.append("Kural gönderimi: merkez HTTP \(reply.status) döndürdü.") }
        }
        let rulesCounter = try nextCounter(&connection)
        let rulesReply = try await client.direct(root: root, keys: keys, device: connection.deviceID, kind: "kurallar", sequence: rulesCounter, plain: Data("{}".utf8))
        try applyRules(rulesReply, connection: &connection, failures: &failures)
        let today = dayKey(Date())
        let totalCounter = try nextCounter(&connection)
        let totalReply = try await client.direct(root: root, keys: keys, device: connection.deviceID, kind: "toplam", sequence: totalCounter, plain: try Wire.json(["tarih": today]))
        try applyTotal(totalReply, day: today, failures: &failures)
        return failures
    }
    private func mailboxReplies(_ mailbox: CenterAddress, keys: ZarfKeys, connection: inout Connection, failures: inout [String]) async throws {
        let replies = try await client.mailboxReplies(mailbox, keys: keys, device: connection.deviceID)
        var last = connection.mailboxLastResponse ?? [:]
        for item in replies {
            guard item.sequence > (last[item.kind] ?? 0) else { continue }
            last[item.kind] = item.sequence
            connection.mailboxLastResponse = last
            applyAddresses(item.reply.addresses, used: nil, connection: &connection)
            switch item.kind {
            case "ozet":
                if item.reply.status == 200 { connection.lastSuccess = Date() }
            case "kural":
                if item.reply.status == 403 { information = "Merkezde kural yazma yetkisi yok." }
            case "kurallar":
                try applyRules(item.reply, connection: &connection, failures: &failures)
            case "toplam":
                if let day = item.reply.body["tarih"] as? String, day == dayKey(Date()) { try applyTotal(item.reply, day: day, failures: &failures) }
            default:
                break
            }
        }
        if replies.isEmpty { connection.mailboxAwaiting = false }
    }
    /// Önceki turların yanıtları alınır; özetler, kararlar ve okuma istekleri kutuya bırakılır.
    private func mailboxRound(_ mailbox: CenterAddress, keys: ZarfKeys, connection: inout Connection) async throws -> [String] {
        var failures: [String] = []
        do { try await mailboxReplies(mailbox, keys: keys, connection: &connection, failures: &failures) }
        catch { failures.append("Posta kutusu yanıtları: " + safeNetworkError(error)) }
        let days = Array(Set(state.dirtyDays + [dayKey(Date())])).sorted().prefix(30)
        for key in days {
            guard let day = state.days[key] else { continue }
            connection.sequence += 1
            let counter = try nextCounter(&connection)
            let body = try Wire.json(Wire.body(day: day, connection: connection, target: state.settings.targetMinutes, pending: state.pending.count, now: Date()))
            // Aynı günün eski özeti kutuda yenisiyle değişir
            try await client.mailboxPost(mailbox, keys: keys, device: connection.deviceID, kind: "ozet", sequence: counter, plain: body, coalesce: "ozet-" + key)
            connection.mailboxAwaiting = true
            let snapshot = connection
            try mutate { next in
                if next.days[key]?.lastSample == day.lastSample { next.dirtyDays.removeAll { $0 == key } }
                next.connection = snapshot
            }
        }
        let sent = state.pending
        if !sent.isEmpty {
            let decisions = sent.map { ["oge": $0.oge, "tur": $0.tur.rawValue, "karar": $0.karar.rawValue] }
            let body = try Wire.json(["schemaVersion": 1, "cihazId": connection.deviceID, "kararlar": decisions])
            let counter = try nextCounter(&connection)
            try await client.mailboxPost(mailbox, keys: keys, device: connection.deviceID, kind: "kural", sequence: counter, plain: body, coalesce: "")
            let ids = Set(sent.map(\.id)); try mutate { $0.pending.removeAll { ids.contains($0.id) } }
        }
        let rulesCounter = try nextCounter(&connection)
        try await client.mailboxPost(mailbox, keys: keys, device: connection.deviceID, kind: "kurallar", sequence: rulesCounter, plain: Data("{}".utf8), coalesce: "kurallar")
        let totalCounter = try nextCounter(&connection)
        try await client.mailboxPost(mailbox, keys: keys, device: connection.deviceID, kind: "toplam", sequence: totalCounter, plain: try Wire.json(["tarih": dayKey(Date())]), coalesce: "toplam")
        connection.mailboxAwaiting = true
        return failures
    }
    private func syncV1() async {
        guard var connection = state.connection, !busy else { return }
        busy = true; defer { busy = false }; var failures: [String] = []
        let days = Array(Set(state.dirtyDays + [dayKey(Date())])).sorted().prefix(30)
        for key in days {
            guard let day = state.days[key] else { continue }
            do {
                connection.sequence += 1
                try mutate { $0.connection = connection }
                let body = try Wire.json(Wire.body(day: day, connection: connection, target: state.settings.targetMinutes, pending: state.pending.count, now: Date()))
                let data = try await client.request(server: connection.server, path: "/v1/ozet", body: body, connection: connection)
                guard (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["ok"] as? Bool == true else { throw AppError.message("Özet yanıtı geçersiz.") }
                connection.lastSuccess = Date()
                try mutate { next in
                    // Do not dequeue a day that received new samples during the network request.
                    if next.days[key]?.lastSample == day.lastSample { next.dirtyDays.removeAll { $0 == key } }
                    next.connection = connection
                }
            } catch { failures.append("Özet: " + safeNetworkError(error)); break }
        }
        let sent = state.pending
        if !sent.isEmpty {
            do {
                let decisions = sent.map { ["oge": $0.oge, "tur": $0.tur.rawValue, "karar": $0.karar.rawValue] }
                let body = try Wire.json(["schemaVersion": 1, "cihazId": connection.deviceID, "kararlar": decisions])
                let data = try await client.request(server: connection.server, path: "/v1/kural", body: body, connection: connection)
                guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], result["ok"] as? Bool == true, result["hatali"] as? Int == 0 else { throw AppError.message("Merkez bazı kararları kabul etmedi.") }
                let ids = Set(sent.map(\.id)); try mutate { $0.pending.removeAll { ids.contains($0.id) } }
            } catch {
                failures.append("Kural gönderimi: " + safeNetworkError(error))
                // Kural yazma izni yoksa (403), Windows istemcisindeki gibi kuyruk birikmesin diye temizlenir.
                // Durum koduna bakılır; hata metni değişebilir.
                if let failure = error as? HTTPFailure, failure.status == 403 {
                    try? mutate { $0.pending.removeAll() }
                    information = "Merkezde kural yazma yetkisi yok; bekleyen kararlar temizlendi."
                }
            }
        }
        do {
            let data = try await client.request(server: connection.server, path: "/v1/kurallar", connection: connection)
            let rules = try storage.decoder.decode(SharedRules.self, from: data)
            guard rules.ok else { throw AppError.message("Kural yanıtı geçersiz.") }
            try mutate { next in
                next.rules.merge(rules)
                // Keep explicit unsent local decisions until the server accepts them.
                for change in next.pending { next.rules.apply(change) }
            }
            connection.lastRuleSuccess = Date()
        } catch { failures.append("Kural alımı: " + safeNetworkError(error)) }
        do {
            let key = dayKey(Date()), data = try await client.request(server: connection.server, path: "/v1/toplam?tarih=" + key, connection: connection)
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], result["ok"] as? Bool == true, result["tarih"] as? String == key, let minutes = result["digerCihazDk"] as? Int else { throw AppError.message("Ortak sayaç yanıtı geçersiz.") }
            try mutate { $0.sharedTotal = SharedTotal(date: key, otherMinutes: minutes, updated: Date()) }
        } catch { failures.append("Ortak sayaç: " + safeNetworkError(error)) }
        connection.lastError = failures.joined(separator: " | ")
        action { try mutate { $0.connection = connection } }
    }
    private func safeNetworkError(_ error: Error) -> String {
        if let error = error as? HTTPFailure { return error.localizedDescription }
        if let error = error as? AppError { return error.localizedDescription }
        return "Bağlantı kurulamadı veya yanıt okunamadı."
    }
    func backup() {
        action { let url = try storage.backup(state); information = "Yedek alındı: " + url.path; NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    func restore() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedFileTypes = ["ctbackup"]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        action {
            let backup = try storage.inspectBackup(url)
            let alert = NSAlert(); alert.messageText = "\(backup.days.count) günlük yedeği geri yükle?"
            alert.informativeText = "Önce mevcut verinin güvenlik yedeği alınır. Yerel kurallar ve ölçümler yedekten döner. Merkez bağlantısı ve merkez sunucusunun verileri değişmez."
            alert.addButton(withTitle: "Geri yükle"); alert.addButton(withTitle: "Vazgeç")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            warnings.dismiss(); previous = nil
            let (restored, safety) = try storage.restore(backup, current: state); state = restored
            information = "Geri yüklendi. Güvenlik yedeği: " + safety.path
        }
    }
    func export(day: Day) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "calisma-\(day.date).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        action {
            let rows = day.applications.values.sorted { $0.seconds > $1.seconds }.map { [Wire.csvCell($0.name), Wire.csvCell($0.category.rawValue), String(Int($0.seconds / 60))].joined(separator: ";") }
            try Data(("uygulama;kategori;dakika\n" + rows.joined(separator: "\n")).utf8).write(to: url, options: .atomic)
        }
    }
}

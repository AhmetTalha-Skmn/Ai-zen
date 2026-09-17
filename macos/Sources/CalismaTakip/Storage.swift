import Foundation
import CryptoKit
import Darwin
import TakipCore

@MainActor final class Storage {
    let root: URL
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    private var lockFD: Int32 = -1
    init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CalismaTakip", isDirectory: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601; decoder.dateDecodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        lockFD = Darwin.open(self.root.appendingPathComponent(".instance.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0 else { throw AppError.message("Veri kilidi açılamadı.") }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(lockFD); lockFD = -1
            throw AppError.message("Aizen zaten çalışıyor. Menü çubuğundaki uygulamayı açın.")
        }
        for name in ["aktivite", "yedekler"] { try FileManager.default.createDirectory(at: self.root.appendingPathComponent(name), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
    }
    deinit { if lockFD >= 0 { Darwin.close(lockFD) } }
    func load<T: Decodable>(_ name: String, default value: T) throws -> T {
        let url = root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return value }
        do { return try decoder.decode(T.self, from: Data(contentsOf: url)) }
        catch { throw AppError.message("\(name) okunamadı. Dosya korunuyor; uygulama veriyi sıfırlamadı.") }
    }
    func save<T: Encodable>(_ value: T, name: String) throws {
        let url = root.appendingPathComponent(name)
        try encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    var stopFile: URL { root.appendingPathComponent("DUR") }
    // Foundation, Objective-C'nin global `Category` typedef'ini de getirir; modül adıyla nitelenir.
    func append(_ sample: Sample, seconds: Double, category: TakipCore.Category) throws {
        let url = root.appendingPathComponent("aktivite/\(dayKey(sample.time)).csv")
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data("zaman;uygulama;baslik;bosta;kategori;sure;kaynak;alanadi\n".utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        let row = [iso(sample.time), sample.app, sample.title, sample.idleSeconds >= 300 ? "1" : "0", category.rawValue, String(Int(seconds.rounded())), "macos", sample.domain].map(Wire.csvCell).joined(separator: ";") + "\n"
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: Data(row.utf8))
    }
    struct Backup: Codable {
        var version = 1
        var created: Date
        var settings: Settings
        var rules: Rules
        var days: [String: Day]
        var activity: [String: Data]
    }
    struct Envelope: Codable { var version = 1; var payload: Data; var sha256: String }
    func backup(_ state: TrackerState, destination: URL? = nil) throws -> URL {
        var files: [String: Data] = [:]; var size = 0
        for url in try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("aktivite"), includingPropertiesForKeys: [.isSymbolicLinkKey]) where Self.activityName(url.lastPathComponent) {
            guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw AppError.message("Yedekte sembolik bağlantı kullanılamaz.") }
            let data = try Data(contentsOf: url); size += data.count
            guard size <= 128 * 1024 * 1024 else { throw AppError.message("Aktivite arşivi 128 MB sınırını aştı; eski kayıtları arşivleyin.") }
            files[url.lastPathComponent] = data
        }
        let payload = try encoder.encode(Backup(created: Date(), settings: state.settings, rules: state.rules, days: state.days, activity: files))
        let envelope = Envelope(payload: payload, sha256: Self.hash(payload))
        let url = destination ?? root.appendingPathComponent("yedekler/\(dayKey(Date()))-\(UUID().uuidString).ctbackup")
        try encoder.encode(envelope).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
    func inspectBackup(_ url: URL) throws -> Backup {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 256 * 1024 * 1024 else { throw AppError.message("Yedek 256 MB sınırını aşıyor.") }
        let envelope = try decoder.decode(Envelope.self, from: Data(contentsOf: url))
        guard envelope.version == 1, Self.hash(envelope.payload) == envelope.sha256 else { throw AppError.message("Yedek bütünlük kontrolü başarısız.") }
        let backup = try decoder.decode(Backup.self, from: envelope.payload)
        guard backup.version == 1, (1...1440).contains(backup.settings.targetMinutes), backup.activity.keys.allSatisfy(Self.activityName), backup.days.keys.allSatisfy(Self.dateName) else { throw AppError.message("Yedek şeması geçersiz.") }
        return backup
    }
    func restore(_ backup: Backup, current: TrackerState) throws -> (TrackerState, URL) {
        let safety = try self.backup(current)
        var next = current
        next.settings = backup.settings; next.settings.focusUntil = nil
        next.rules = backup.rules; next.days = backup.days
        next.pending = []; next.sharedTotal = nil; next.dirtyDays = Array(backup.days.keys)
        // Stage every file before touching current data, and keep the old directory for rollback.
        let staging = root.appendingPathComponent("restore-\(UUID().uuidString)", isDirectory: true)
        let old = root.appendingPathComponent("restore-old-\(UUID().uuidString)", isDirectory: true)
        let activity = root.appendingPathComponent("aktivite", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        for (name, data) in backup.activity {
            let file = staging.appendingPathComponent(name)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        try FileManager.default.moveItem(at: activity, to: old)
        do {
            try FileManager.default.moveItem(at: staging, to: activity)
            try save(next, name: "state.json")
        } catch {
            try? FileManager.default.removeItem(at: activity)
            do { try FileManager.default.moveItem(at: old, to: activity) }
            catch { throw AppError.message("Geri alma tamamlanamadı. Güvenlik yedeği: \(safety.path)") }
            throw error
        }
        try? FileManager.default.removeItem(at: old)
        return (next, safety)
    }
    func retain(days: Int, now: Date) throws {
        let cutoff = dayKey(Calendar.current.date(byAdding: .day, value: -max(1, days), to: now)!)
        for file in try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("aktivite"), includingPropertiesForKeys: nil) where Self.activityName(file.lastPathComponent) && String(file.lastPathComponent.prefix(10)) < cutoff { try FileManager.default.removeItem(at: file) }
        let backups = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("yedekler"), includingPropertiesForKeys: [.creationDateKey]).filter { $0.pathExtension == "ctbackup" }.sorted {
            ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
        }
        for file in backups.dropFirst(8) { try FileManager.default.removeItem(at: file) }
    }
    // Saf yardımcılar: durum okumaz. nonisolated olmaları @MainActor sınıf dışından ve fonksiyon
    // değeri olarak (allSatisfy) kullanılmalarını derleyici uyarısız kılar.
    nonisolated static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    nonisolated static func dateName(_ name: String) -> Bool { name.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
    nonisolated static func activityName(_ name: String) -> Bool { name.hasSuffix(".csv") && dateName(String(name.dropLast(4))) }
}

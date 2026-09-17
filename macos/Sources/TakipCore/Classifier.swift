import Foundation

public enum Classifier {
    static func contains(_ value: String, _ patterns: [String]) -> Bool {
        patterns.contains { !$0.isEmpty && value.range(of: $0, options: .caseInsensitive) != nil }
    }
    static func domainMatches(_ host: String, _ patterns: [String]) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return !host.isEmpty && patterns.contains {
            let rule = $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return !rule.isEmpty && (host == rule || host.hasSuffix("." + rule))
        }
    }
    public static func classify(_ sample: Sample, rules: Rules) -> Classification {
        if sample.idleSeconds >= 300 { return Classification(category: .idle, counted: false, mayBlock: false) }
        if contains(sample.title, rules.calisma.baslik) || domainMatches(sample.domain, rules.calisma.alanadi) {
            return Classification(category: .work, counted: true, mayBlock: false)
        }
        let protected = contains(sample.app, rules.aslaEngelleme) || contains(sample.bundle, rules.aslaEngelleme)
        if contains(sample.app, rules.yasakli.surec) || contains(sample.bundle, rules.yasakli.surec) || contains(sample.title, rules.yasakli.baslik) || domainMatches(sample.domain, rules.yasakli.alanadi) {
            return Classification(category: .other, counted: false, mayBlock: !protected)
        }
        if contains(sample.app, rules.calisma.surec) || contains(sample.bundle, rules.calisma.surec) {
            return Classification(category: .work, counted: true, mayBlock: false)
        }
        return Classification(category: .uncertain, counted: rules.belirsizSayilsin, mayBlock: false)
    }
    public static func decided(_ item: UnknownItem, rules: Rules) -> Bool {
        contains(item.app, rules.calisma.surec + rules.yasakli.surec + rules.bilerekBelirsiz) ||
        contains(item.title, rules.calisma.baslik + rules.yasakli.baslik + rules.bilerekBelirsiz) ||
        domainMatches(item.domain, rules.calisma.alanadi + rules.yasakli.alanadi + rules.bilerekBelirsiz)
    }
    public static func elapsed(previous: Date?, now: Date) -> Double {
        guard let previous else { return 0 }
        let delta = now.timeIntervalSince(previous)
        // Sleep, logout, a suspended process and clock jumps never create study time.
        return delta > 0 && delta <= 20 ? delta : 0
    }
}
public enum Wire {
    public static func normalizedCode(_ code: String) -> String {
        code.uppercased().filter { $0.isASCII && ($0.isNumber || $0.isLetter) }
            .replacingOccurrences(of: "I", with: "1").replacingOccurrences(of: "L", with: "1").replacingOccurrences(of: "O", with: "0")
    }
    public static func body(day: Day, connection: Connection, target: Int, pending: Int, now: Date) -> [String: Any] {
        // Parça parça ve açık tiplerle kurulur: iç içe tek büyük karışık sözlük literali derleyicide
        // "unable to type-check this expression in reasonable time" hatasına yol açabilir.
        let sortedApps = day.applications.values.sorted { $0.seconds > $1.seconds }.prefix(80)
        var apps: [[String: Any]] = []
        for total in sortedApps {
            var entry: [String: Any] = [:]
            entry["ad"] = String(total.name.prefix(100))
            entry["dakika"] = Int((total.seconds / 60).rounded())
            entry["kategori"] = total.category.rawValue
            entry["kaynak"] = "macos"
            apps.append(entry)
        }
        let coverage: [String: Bool] = [
            "uygulamaOzetleri": true, "pencereBasliklari": false, "alanAdlari": false, "tamUrl": false,
            "aramaTerimleri": false, "ekranGoruntusu": false, "tusKaydi": false
        ]
        var totals: [String: Int] = [:]
        totals["calismaDk"] = day.minutes
        totals["digerDk"] = Int(day.otherSeconds / 60)
        totals["bostaDk"] = Int(day.idleSeconds / 60)
        totals["kayitDk"] = Int((day.workSeconds + day.otherSeconds + day.idleSeconds) / 60)
        totals["hedefDk"] = target
        var sync: [String: Any] = [:]
        sync["bekleyenKarar"] = pending
        sync["sonBasariliGonderimUtc"] = connection.lastSuccess.map { iso($0) } ?? ""
        sync["sonKuralAlimiUtc"] = connection.lastRuleSuccess.map { iso($0) } ?? ""
        sync["hata"] = connection.lastError
        sync["bildirimUtc"] = iso(now)
        var health: [String: Any] = [:]
        health["yerelIzleyiciCalisiyor"] = day.lastSample.map { now.timeIntervalSince($0) < 30 } ?? false
        health["sonOrnekUtc"] = day.lastSample.map { iso($0) } ?? ""
        health["kayitSatiri"] = 0
        health["senkron"] = sync
        let noItems: [[String: Any]] = []
        var body: [String: Any] = [:]
        body["schemaVersion"] = 1
        body["cihazId"] = connection.deviceID
        body["cihazAdi"] = connection.deviceName
        body["gonderildiUtc"] = iso(now)
        body["clientTarih"] = day.date
        body["zamanDilimiOfsetDk"] = TimeZone.current.secondsFromGMT(for: now) / 60
        body["sira"] = connection.sequence
        body["veriKapsami"] = coverage
        body["ozet"] = totals
        body["uygulamalar"] = apps
        body["basliklar"] = noItems
        body["alanlar"] = noItems
        body["health"] = health
        return body
    }
    public static func json(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    public static func csvCell(_ value: String) -> String {
        let clean = value.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        // A spreadsheet must not execute titles/application names as formulas.
        let safe = clean.first.map { "=+-@".contains($0) } == true ? "'" + clean : clean
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

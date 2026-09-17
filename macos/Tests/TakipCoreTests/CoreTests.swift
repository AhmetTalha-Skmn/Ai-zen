import XCTest
@testable import TakipCore

final class CoreTests: XCTestCase {
    func testNeutralRules() {
        let rules = Rules()
        XCTAssertTrue(rules.rows.isEmpty)
        XCTAssertEqual(Classifier.classify(Sample(app: "Unknown"), rules: rules).category, .uncertain)
        XCTAssertTrue(Classifier.classify(Sample(app: "Unknown"), rules: rules).counted)
    }
    func testIdleOverridesAllowedTitle() {
        var rules = Rules(); rules.calisma.baslik = ["Lesson"]
        let result = Classifier.classify(Sample(app: "Editor", title: "Lesson", idleSeconds: 300), rules: rules)
        XCTAssertEqual(result.category, .idle); XCTAssertFalse(result.counted); XCTAssertFalse(result.mayBlock)
    }
    func testAllowedTitleOverridesForbiddenApplication() {
        var rules = Rules(); rules.calisma.baslik = ["Exact lesson title"]; rules.yasakli.surec = ["Browser"]
        XCTAssertEqual(Classifier.classify(Sample(app: "Browser", title: "Exact lesson title"), rules: rules).category, .work)
    }
    func testForbiddenDomainOverridesAllowedApplication() {
        var rules = Rules(); rules.calisma.surec = ["Browser"]; rules.yasakli.alanadi = ["example.org"]
        let result = Classifier.classify(Sample(app: "Browser", domain: "sub.example.org"), rules: rules)
        XCTAssertEqual(result.category, .other); XCTAssertTrue(result.mayBlock)
    }
    func testDomainBoundary() {
        var rules = Rules(); rules.yasakli.alanadi = ["example.org"]
        XCTAssertEqual(Classifier.classify(Sample(app: "Browser", domain: "badexample.org"), rules: rules).category, .uncertain)
        XCTAssertEqual(Classifier.classify(Sample(app: "Browser", domain: "example.org.attacker.test"), rules: rules).category, .uncertain)
        XCTAssertEqual(Classifier.classify(Sample(app: "Browser", domain: "SUB.EXAMPLE.ORG."), rules: rules).category, .other)
    }
    func testCriticalApplicationCannotBeBlocked() {
        var rules = Rules(); rules.yasakli.surec = ["Finder"]
        let result = Classifier.classify(Sample(app: "Finder"), rules: rules)
        XCTAssertEqual(result.category, .other); XCTAssertFalse(result.mayBlock)
    }
    func testUncertainNeverBlocksAndCanBeExcluded() {
        var rules = Rules(); rules.belirsizSayilsin = false
        let result = Classifier.classify(Sample(app: "New app"), rules: rules)
        XCTAssertFalse(result.counted); XCTAssertFalse(result.mayBlock)
    }
    func testClockJumpsAndSleepDoNotCount() {
        let date = Date(timeIntervalSince1970: 10000)
        XCTAssertEqual(Classifier.elapsed(previous: nil, now: date), 0)
        XCTAssertEqual(Classifier.elapsed(previous: date, now: date.addingTimeInterval(10)), 10)
        XCTAssertEqual(Classifier.elapsed(previous: date, now: date.addingTimeInterval(21)), 0)
        XCTAssertEqual(Classifier.elapsed(previous: date, now: date.addingTimeInterval(-1)), 0)
    }
    func testCounterAndUnknownAggregation() {
        let sample = Sample(app: "Editor", title: "Local secret", domain: "private.example")
        var day = Day(date: "2026-09-16")
        for _ in 0..<6 { day.add(sample, seconds: 10, classification: Classifier.classify(sample, rules: Rules())) }
        XCTAssertEqual(day.minutes, 1); XCTAssertEqual(day.unknown.count, 1)
        XCTAssertEqual(day.unknown.values.first?.seconds, 60)
    }
    func testDayBoundaryUsesSpecifiedTimeZone() {
        let date = ISO8601DateFormatter().date(from: "2026-09-16T22:30:00Z")!
        XCTAssertEqual(dayKey(date, timeZone: TimeZone(secondsFromGMT: 10800)!), "2026-09-17")
        XCTAssertEqual(dayKey(date, timeZone: TimeZone(secondsFromGMT: 0)!), "2026-09-16")
    }
    func testSharedTotalExpiresAndDoesNotLeakAcrossDays() {
        let now = Date()
        XCTAssertEqual(SharedTotal(date: dayKey(now), otherMinutes: 60, updated: now).usableMinutes(now: now), 60)
        XCTAssertEqual(SharedTotal(date: dayKey(now), otherMinutes: 60, updated: now.addingTimeInterval(-1801)).usableMinutes(now: now), 0)
        XCTAssertEqual(SharedTotal(date: "2000-01-01", otherMinutes: 60, updated: now).usableMinutes(now: now), 0)
        XCTAssertEqual(SharedTotal(date: dayKey(now), otherMinutes: 60, updated: now.addingTimeInterval(61)).usableMinutes(now: now), 0)
    }
    func testSharedRulesWinAndLocalExceptionsSurvive() {
        var local = Rules(); local.calisma.surec = ["Editor", "Local"]; local.belirsizSayilsin = false
        var remote = Rules(); remote.yasakli.surec = ["Editor"]; remote.aslaEngelleme = []
        local.merge(SharedRules(rules: remote))
        XCTAssertEqual(local.calisma.surec, ["Local"])
        XCTAssertEqual(local.yasakli.surec, ["Editor"])
        XCTAssertTrue(local.aslaEngelleme.contains("Finder")); XCTAssertFalse(local.belirsizSayilsin)
    }
    func testDeletionDoesNotDeleteNewDecision() {
        var rules = Rules(); rules.yasakli.surec = ["Editor"]
        rules.merge(SharedRules(rules: Rules(), deleted: [RuleChange(value: "Editor", kind: .process, decision: .work)]))
        XCTAssertEqual(rules.yasakli.surec, ["Editor"])
        rules.merge(SharedRules(rules: Rules(), deleted: [RuleChange(value: "Editor", kind: .process, decision: .forbidden)]))
        XCTAssertTrue(rules.yasakli.surec.isEmpty)
    }
    func testCodeNormalization() {
        XCTAssertEqual(Wire.normalizedCode(" abci-l0o1-2345 "), "ABC110012345")
    }
    func testSummaryContainsNoCapturedTitlesOrDomains() throws {
        let sample = Sample(app: "Editor", title: "PRIVATE TITLE", domain: "private.example")
        var day = Day(date: "2026-09-16")
        day.add(sample, seconds: 10, classification: Classifier.classify(sample, rules: Rules()))
        let connection = Connection(server: "http://localhost:8787", deviceID: "test-device", deviceName: "Test Mac", consentAt: Date())
        let data = try Wire.json(Wire.body(day: day, connection: connection, target: 240, pending: 0, now: Date()))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("PRIVATE TITLE")); XCTAssertFalse(text.contains("private.example"))
        XCTAssertTrue(text.contains("Editor")); XCTAssertTrue(text.contains("\"tamUrl\":false"))
    }
    func testSpreadsheetFormulaEscaping() {
        XCTAssertEqual(Wire.csvCell("=SUM(A1)"), "\"'=SUM(A1)\"")
        XCTAssertEqual(Wire.csvCell("a\"b\nc"), "\"a\"\"b c\"")
    }
    func testInstallTypeDefaultsAndOverrides() throws {
        var settings = Settings()
        XCTAssertEqual(settings.effectiveInstallType, .individual)
        XCTAssertTrue(settings.remindersEnabled); XCTAssertTrue(settings.screenLockEnabled)
        settings.installType = "sirket"
        XCTAssertFalse(settings.remindersAvailable); XCTAssertFalse(settings.remindersEnabled); XCTAssertFalse(settings.screenLockEnabled)
        settings.reminders = true; settings.screenLock = true
        XCTAssertFalse(settings.remindersEnabled, "Şirket türünde hatırlatma açılamaz")
        XCTAssertTrue(settings.screenLockEnabled)
        settings.installType = "ozel"; settings.reminders = nil; settings.screenLock = nil
        XCTAssertTrue(settings.remindersEnabled); XCTAssertFalse(settings.screenLockEnabled)
        settings.installType = "Bireysel"; settings.reminders = false
        XCTAssertEqual(settings.effectiveInstallType, .individual); XCTAssertFalse(settings.remindersEnabled)
        settings.installType = "bilinmeyen"
        XCTAssertEqual(settings.effectiveInstallType, .individual)
        // Eski state.json ayarları yeni alanlar olmadan çözülür ve bireysel davranır.
        let old = #"{"targetMinutes":240,"paused":false,"retentionDays":90}"#
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(old.utf8))
        XCTAssertNil(decoded.installType); XCTAssertTrue(decoded.remindersEnabled); XCTAssertTrue(decoded.screenLockEnabled)
    }
    func testWikiFilteringBlocksAndLinks() {
        let body = "# A\n\nOrtak.\n<!-- yalniz: sirket -->\nŞirket.\n<!-- /yalniz -->\n<!-- yalniz: windows -->\nWin.\n<!-- /yalniz -->\n- bir\n<!-- yalniz: mac bireysel -->\n- mac\n<!-- /yalniz -->\n- iki\n  devam\n\n| x | y |\n|---|---|\n| 1 | 2 |\n\n1. ilk\n2. ikinci"
        let individual = Wiki.suz(body, tur: "bireysel")
        XCTAssertFalse(individual.contains("Şirket.")); XCTAssertFalse(individual.contains("Win.")); XCTAssertFalse(individual.contains("yalniz"))
        XCTAssertEqual(Wiki.bloklar(individual), [.baslik(1, "A"), .paragraf("Ortak."), .liste(["bir", "mac", "iki devam"], sirali: false), .tablo([["x", "y"], ["1", "2"]]), .liste(["ilk", "ikinci"], sirali: true)])
        let company = Wiki.suz(body, tur: "sirket")
        XCTAssertTrue(company.contains("Şirket.")); XCTAssertFalse(company.contains("- mac"))
        let nested = Wiki.suz("<!-- yalniz: mac -->\ndış\n<!-- yalniz: sirket -->\niç\n<!-- /yalniz -->\nson\n<!-- /yalniz -->", tur: "bireysel")
        XCTAssertEqual(nested, "dış\nson")
        XCTAssertEqual(Wiki.baglantilariCevir("[Ayarlar](ayarlar) ve [gizli](hatirlatmalar) kod", adlar: ["ayarlar"]), "[Ayarlar](wiki:ayarlar) ve gizli kod")
    }
    func testGeneratedWikiContent() {
        let individual = Wiki.sayfalar(tur: "bireysel").map(\.ad)
        let company = Wiki.sayfalar(tur: "sirket").map(\.ad)
        XCTAssertEqual(individual.first, "baslarken")
        XCTAssertTrue(individual.contains("hatirlatmalar")); XCTAssertFalse(company.contains("hatirlatmalar"))
        for type in InstallType.allCases {
            for page in Wiki.sayfalar(tur: type.rawValue) {
                XCTAssertFalse(page.govde.contains("yalniz"), page.ad)
                XCTAssertFalse(page.govde.contains("Kontrol panel"), page.ad + ": Windows metni Mac içeriğine girmemeli")
                XCTAssertFalse(Wiki.bloklar(page.govde).isEmpty, page.ad)
            }
        }
    }
}

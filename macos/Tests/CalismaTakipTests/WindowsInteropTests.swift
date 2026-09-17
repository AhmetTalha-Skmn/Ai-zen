import XCTest
import TakipCore
@testable import CalismaTakip

/// Windows ile birlikte çalışma testleri.
///
/// Fixture'lar gerçek Windows kaynaklarından üretilir (scripts/generate-windows-interop.ps1):
/// Mac merkezine Windows istemcisinin gerçekten gönderdiği baytlar verilir, Mac istemcisine
/// Windows merkezinin gerçek yanıtları okutulur. Beklenen sonuç Windows'un kendi davranışıdır.
final class WindowsInteropTests: XCTestCase {
    private struct EnrolledCenter {
        let center: Center
        let deviceID: String
        let key: Data
        let root: URL

        /// istemci-gonderici.ps1 ile aynı imza: POST'ta gövde, GET'te yol + sorgu.
        func request(_ method: String, _ target: String, body: Data = Data(), skew: Int = 0) -> IncomingRequest {
            let timestamp = String(Int(Date().timeIntervalSince1970) + skew)
            let signed = method == "GET" ? Data(target.utf8) : body
            return IncomingRequest(method: method, target: target, headers: [
                "x-ct-cihaz": deviceID,
                "x-ct-zaman": timestamp,
                "x-ct-imza": Crypto.signature(key: key, timestamp: timestamp, body: signed)
            ], body: body)
        }
    }

    private func fixture(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func bytes(_ values: [String: Any], _ name: String) throws -> Data {
        let text = try XCTUnwrap(values[name] as? String, "Fixture alanı yok: \(name)")
        return try XCTUnwrap(Data(base64Encoded: text), "Fixture alanı base64 değil: \(name)")
    }

    private func replacing(_ data: Data, _ values: [String: String]) throws -> Data {
        var text = try XCTUnwrap(String(data: data, encoding: .utf8))
        for (placeholder, value) in values {
            XCTAssertTrue(text.contains(placeholder), "Fixture yer tutucusu yok: \(placeholder)")
            text = text.replacingOccurrences(of: placeholder, with: value)
        }
        return Data(text.utf8)
    }

    /// Mac merkezinde kod üretir ve Windows istemcisinin gerçek kayıt gövdesiyle eşleşir.
    @MainActor private func enrollWindowsDevice(_ values: [String: Any], writeRules: Bool = false) throws -> EnrolledCenter {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ct-interop-" + UUID().uuidString)
        let storage = try Storage(root: root)
        var keys: [String: Data] = [:]
        let credentials = CenterCredentials(read: { account in
            guard let key = keys[account] else { throw AppError.message("Test anahtarı yok") }
            return key
        }, write: { keys[$1] = $0 }, remove: { keys[$0] = nil })
        let center = try Center(storage: storage, credentials: credentials)
        let code = try center.code(name: "Windows Test PC")
        let template = try bytes(values, "kayitIstegiBase64")
        // istemci-kayit.ps1 kodu normalleştirip gönderir.
        let body = try replacing(template, ["@@KOD@@": Wire.normalizedCode(code)])
        let response = center.handle(IncomingRequest(method: "POST", target: "/v1/kayit", headers: [:], body: body))
        XCTAssertEqual(response.status, 200, "Windows kayıt isteği reddedildi: \(response.json)")
        let deviceID = try XCTUnwrap(response.json["cihazId"] as? String)
        let packet = try XCTUnwrap(response.json["anahtar"] as? [String: Any])
        let key = try Crypto.open(packet, code: code)
        if writeRules {
            var device = try XCTUnwrap(center.state.devices.first(where: { $0.id == deviceID }))
            device.canWriteRules = true
            try center.updateDevice(device)
        }
        return EnrolledCenter(center: center, deviceID: deviceID, key: key, root: root)
    }

    // MARK: Windows istemcisi → Mac merkezi

    func testWindowsEnrollmentRequestIsAcceptedByMacCenter() async throws {
        let values = try fixture("windows-interop")
        try await MainActor.run {
            let enrolled = try self.enrollWindowsDevice(values)
            defer { try? FileManager.default.removeItem(at: enrolled.root) }
            // Windows istemcisi dönen kimliği Test-DagitikCihazKimligi ile doğrular.
            XCTAssertNotNil(enrolled.deviceID.range(of: #"^[A-Za-z0-9_-]{3,64}$"#, options: .regularExpression))
            XCTAssertEqual(enrolled.key.count, 32)
        }
    }

    func testWindowsDailySummaryWithDotNetTimestampIsAccepted() async throws {
        let values = try fixture("windows-interop")
        let template = try bytes(values, "ozetBase64")
        let expectedMinutes = try XCTUnwrap(values["ozetCalismaDk"] as? Int)
        // Windows [DateTime]::ToString('o') saniye kesrini yedi basamakla yazar.
        let text = try XCTUnwrap(String(data: template, encoding: .utf8))
        XCTAssertNotNil(text.range(of: #""gonderildiUtc":"[0-9T:-]+\.[0-9]{7}Z""#, options: .regularExpression))
        try await MainActor.run {
            let enrolled = try self.enrollWindowsDevice(values)
            defer { try? FileManager.default.removeItem(at: enrolled.root) }
            let today = dayKey(Date())
            let body = try self.replacing(template, ["@@CIHAZ@@": enrolled.deviceID, "@@TARIH@@": today])
            let response = enrolled.center.handle(enrolled.request("POST", "/v1/ozet", body: body))
            XCTAssertEqual(response.status, 200, "Windows özeti reddedildi: \(response.json)")
            XCTAssertEqual(enrolled.center.total(day: today), expectedMinutes)
        }
    }

    func testClockSkewToleranceMatchesWindowsCenter() async throws {
        let values = try fixture("windows-interop")
        try await MainActor.run {
            let enrolled = try self.enrollWindowsDevice(values)
            defer { try? FileManager.default.removeItem(at: enrolled.root) }
            // Windows merkezi ±900 sn kabul eder (merkez-sunucu.ps1). Saati 10 dk kaymış bir cihaz
            // iki merkezde de aynı sonucu almalı.
            XCTAssertEqual(enrolled.center.handle(enrolled.request("GET", "/v1/kurallar", skew: -600)).status, 200)
            XCTAssertEqual(enrolled.center.handle(enrolled.request("GET", "/v1/kurallar", skew: 600)).status, 200)
            XCTAssertEqual(enrolled.center.handle(enrolled.request("GET", "/v1/kurallar", skew: -1000)).status, 401)
        }
    }

    func testWindowsRulePushesAreAppliedOnlyWithPermission() async throws {
        let values = try fixture("windows-interop")
        let multiple = try bytes(values, "kuralItmeCokluBase64")
        let single = try bytes(values, "kuralItmeTekBase64")
        let title = try XCTUnwrap(values["turkceBaslik"] as? String)
        try await MainActor.run {
            let denied = try self.enrollWindowsDevice(values)
            defer { try? FileManager.default.removeItem(at: denied.root) }
            let deniedBody = try self.replacing(multiple, ["@@CIHAZ@@": denied.deviceID])
            XCTAssertEqual(denied.center.handle(denied.request("POST", "/v1/kural", body: deniedBody)).status, 403)

            let allowed = try self.enrollWindowsDevice(values, writeRules: true)
            defer { try? FileManager.default.removeItem(at: allowed.root) }
            let allowedBody = try self.replacing(multiple, ["@@CIHAZ@@": allowed.deviceID])
            let response = allowed.center.handle(allowed.request("POST", "/v1/kural", body: allowedBody))
            XCTAssertEqual(response.status, 200, "Windows kural gövdesi reddedildi: \(response.json)")
            XCTAssertEqual(response.json["hatali"] as? Int, 0)
            XCTAssertEqual(allowed.center.state.rules.calisma.alanadi, ["example.edu"])
            XCTAssertEqual(allowed.center.state.rules.yasakli.surec, ["GameLauncher"])
            XCTAssertEqual(allowed.center.state.rules.calisma.baslik, [title])

            // PowerShell tek kararı da dizi olarak yazar; Mac merkezi bunu kabul etmeli.
            let singleBody = try self.replacing(single, ["@@CIHAZ@@": allowed.deviceID])
            let one = allowed.center.handle(allowed.request("POST", "/v1/kural", body: singleBody))
            XCTAssertEqual(one.status, 200, "Tek kararlı Windows gövdesi reddedildi: \(one.json)")
            XCTAssertEqual(allowed.center.state.rules.bilerekBelirsiz, ["NoteApp"])
        }
    }

    func testWindowsSignedGetRequestsAreAccepted() async throws {
        let values = try fixture("windows-interop")
        try await MainActor.run {
            let enrolled = try self.enrollWindowsDevice(values)
            defer { try? FileManager.default.removeItem(at: enrolled.root) }
            // istemci-gonderici.ps1 '/v1/kurallar' ve '/v1/toplam?tarih=yyyy-MM-dd' metnini imzalar.
            XCTAssertEqual(enrolled.center.handle(enrolled.request("GET", "/v1/kurallar")).status, 200)
            let total = enrolled.center.handle(enrolled.request("GET", "/v1/toplam?tarih=" + dayKey(Date())))
            XCTAssertEqual(total.status, 200)
            XCTAssertNotNil(total.json["digerCihazDk"] as? Int)
        }
    }

    // MARK: Windows merkezi → Mac istemcisi

    func testWindowsCenterRulesMergeLikeWindowsClient() throws {
        let values = try fixture("windows-interop")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try bytes(values, "kurallarYanitiBase64")
        let before = try bytes(values, "yerelKurallarOnceBase64")
        let after = try bytes(values, "yerelKurallarSonraBase64")
        let shared = try decoder.decode(SharedRules.self, from: response)
        XCTAssertTrue(shared.ok)
        var local = try decoder.decode(Rules.self, from: before)
        let protected = local.aslaEngelleme
        // Beklenen, Windows istemcisinin Merge-YerelKurallar ile aynı girdiden ürettiği dosyadır.
        let expected = try decoder.decode(Rules.self, from: after)
        local.merge(shared)
        for kind in RuleKind.allCases {
            XCTAssertEqual(Set(local.calisma[kind]), Set(expected.calisma[kind]), "calisma.\(kind.rawValue)")
            XCTAssertEqual(Set(local.yasakli[kind]), Set(expected.yasakli[kind]), "yasakli.\(kind.rawValue)")
        }
        XCTAssertEqual(Set(local.bilerekBelirsiz), Set(expected.bilerekBelirsiz))
        XCTAssertEqual(local.aslaEngelleme, protected, "aslaEngelleme merkezden taşınmaz")
    }

    func testWindowsCenterEnrollmentResponseOpensOnMac() throws {
        let values = try fixture("windows-interop")
        let data = try bytes(values, "kayitYanitiBase64")
        let code = try XCTUnwrap(values["kayitYanitiKod"] as? String)
        // Client.enroll ile aynı okuma.
        let reply = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(reply["ok"] as? Bool, true)
        let id = try XCTUnwrap(reply["cihazId"] as? String)
        XCTAssertNotNil(id.range(of: #"^[A-Za-z0-9_-]{3,64}$"#, options: .regularExpression))
        let packet = try XCTUnwrap(reply["anahtar"] as? [String: Any])
        let key = try Crypto.open(packet, code: code)
        XCTAssertEqual(key.base64EncodedString(), values["kayitYanitiAnahtar"] as? String)
    }

    func testWindowsCenterTotalResponseTypes() throws {
        let values = try fixture("windows-interop")
        let data = try bytes(values, "toplamYanitiBase64")
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // Engine.sync aynı tip dönüşümlerini yapar.
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertNotNil(result["tarih"] as? String)
        XCTAssertEqual(result["digerCihazDk"] as? Int, 45)
    }

    // MARK: Windows protokol vektörleri (uyumluluk/protokol-vektorleri.json)

    func testWindowsProtocolVectors() throws {
        let vectors = try fixture("windows-vectors")
        let keyText = try XCTUnwrap(vectors["anahtarBase64"] as? String)
        let key = try XCTUnwrap(Data(base64Encoded: keyText))

        for item in try XCTUnwrap(vectors["hmac"] as? [[String: Any]]) {
            let timestamp = try XCTUnwrap(item["zaman"] as? String)
            let body = try XCTUnwrap(item["govde"] as? String)
            let name = item["ad"] as? String ?? ""
            XCTAssertEqual(Crypto.signature(key: key, timestamp: timestamp, body: Data(body.utf8)), item["imzaHex"] as? String, name)
        }

        for item in try XCTUnwrap(vectors["kodNormallestirme"] as? [[String: Any]]) {
            let input = try XCTUnwrap(item["girdi"] as? String)
            XCTAssertEqual(Wire.normalizedCode(input), item["cikti"] as? String, input)
        }

        let summary = try XCTUnwrap(vectors["kodOzeti"] as? [String: Any])
        XCTAssertEqual(summary["tur"] as? Int, 120000, "CTLegacyCrypto tur sayısı Windows ile aynı olmalı")
        let summaryCode = try XCTUnwrap(summary["kod"] as? String)
        let summarySalt = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(summary["tuzBase64"] as? String)))
        let summaryHash = try Crypto.derive(code: summaryCode, salt: summarySalt, count: 32)
        XCTAssertEqual(summaryHash.base64EncodedString(), summary["ozetBase64"] as? String)

        let derivedVector = try XCTUnwrap(vectors["turetilen64"] as? [String: Any])
        let derivedCode = try XCTUnwrap(derivedVector["kod"] as? String)
        let derivedSalt = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(derivedVector["tuzBase64"] as? String)))
        let derived = try Crypto.derive(code: derivedCode, salt: derivedSalt)
        XCTAssertEqual(derived.map { String(format: "%02x", $0) }.joined(), derivedVector["hex"] as? String)

        let envelope = try XCTUnwrap(vectors["anahtarZarfi"] as? [String: Any])
        let envelopeCode = try XCTUnwrap(envelope["kod"] as? String)
        let wrongCode = try XCTUnwrap(envelope["yanlisKod"] as? String)
        let opened = try Crypto.open(envelope, code: envelopeCode)
        XCTAssertEqual(opened.base64EncodedString(), envelope["beklenenAnahtar"] as? String)
        XCTAssertThrowsError(try Crypto.open(envelope, code: wrongCode))
        var tampered = envelope
        tampered["etiket"] = Data(repeating: 0, count: 32).base64EncodedString()
        XCTAssertThrowsError(try Crypto.open(tampered, code: envelopeCode))
    }

    /// Protokol v2 (uyumluluk/PROTOKOL-V2.md): Windows'un sabit anahtar, IV ve zamanla ürettiği zarflar
    /// Mac'te birebir yeniden üretilmeli ve açılmalı.
    func testWindowsProtocolV2EnvelopeVectors() throws {
        let vectors = try fixture("windows-vectors")
        let v2 = try XCTUnwrap(vectors["zarfV2"] as? [String: Any], "windows-vectors.json v2 bölümü yok")
        let deviceKey = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(v2["cihazAnahtariBase64"] as? String)))
        let keys = Zarf.keys(deviceKey: deviceKey)
        XCTAssertEqual(Zarf.hex(keys.encryption), v2["sifreHex"] as? String)
        XCTAssertEqual(Zarf.hex(keys.signing), v2["imzaHex"] as? String)
        XCTAssertEqual(keys.mailboxToken, v2["postaJetonu"] as? String)
        XCTAssertEqual(Zarf.sha256Hex(Data(keys.mailboxToken.utf8)), v2["postaJetonuOzeti"] as? String)

        for (name, textField) in [("istek", "istekMetni"), ("yanit", "yanitMetni")] {
            let expected = try XCTUnwrap(v2[name] as? [String: Any])
            let text = try XCTUnwrap(v2[textField] as? String)
            let iv = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(expected["iv"] as? String)))
            let device = try XCTUnwrap(expected["cihaz"] as? String)
            let kind = try XCTUnwrap(expected["tur"] as? String)
            let direction = try XCTUnwrap(expected["yon"] as? String)
            let sequence = try XCTUnwrap((expected["sayac"] as? NSNumber)?.int64Value)
            let time = try XCTUnwrap((expected["zaman"] as? NSNumber)?.int64Value)
            let sealed = try Zarf.seal(Data(text.utf8), keys: keys, device: device, kind: kind, direction: direction, sequence: sequence, time: time, iv: iv)
            XCTAssertEqual(sealed["veri"] as? String, expected["veri"] as? String, name)
            XCTAssertEqual(sealed["etiket"] as? String, expected["etiket"] as? String, name)
            XCTAssertEqual(String(data: try Zarf.open(expected, keys: keys), encoding: .utf8), text, name)
        }

        var tampered = try XCTUnwrap(v2["istek"] as? [String: Any])
        tampered["sayac"] = 43
        XCTAssertThrowsError(try Zarf.open(tampered, keys: keys), "Sayacı değiştirilmiş zarf reddedilmeli")
        var textual = try XCTUnwrap(v2["istek"] as? [String: Any])
        textual["sayac"] = "42"
        XCTAssertFalse(Zarf.isValid(textual), "Metin sayaç geçersiz")
        let reflected = try XCTUnwrap(v2["istek"] as? [String: Any])
        var asReply = reflected
        asReply["yon"] = "yanit"
        XCTAssertThrowsError(try Zarf.open(asReply, keys: keys), "İstek yanıt diye yansıtılamaz")
        XCTAssertThrowsError(try Zarf.open(reflected, keys: Zarf.keys(deviceKey: Data(repeating: 7, count: 32))))

        let enrollment = try XCTUnwrap(vectors["kayitV2"] as? [String: Any])
        let derived = try Zarf.enrollment(code: try XCTUnwrap(enrollment["kod"] as? String))
        XCTAssertEqual(enrollment["tur"] as? Int, 120000)
        XCTAssertEqual(derived.master.base64EncodedString(), enrollment["anaAnahtarBase64"] as? String)
        XCTAssertEqual(derived.channel, enrollment["kanal"] as? String)
        XCTAssertTrue(Zarf.isChannel(derived.channel))
        XCTAssertEqual(Zarf.hex(derived.keys.encryption), enrollment["sifreHex"] as? String)
        XCTAssertEqual(Zarf.hex(derived.keys.signing), enrollment["imzaHex"] as? String)
        XCTAssertEqual(derived.keys.mailboxToken, enrollment["postaJetonu"] as? String)
        let request = try XCTUnwrap(enrollment["istek"] as? [String: Any])
        XCTAssertEqual(String(data: try Zarf.open(request, keys: derived.keys), encoding: .utf8), enrollment["istekMetni"] as? String)
    }
}

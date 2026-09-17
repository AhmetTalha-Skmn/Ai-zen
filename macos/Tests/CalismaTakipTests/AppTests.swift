import XCTest
import TakipCore
@testable import CalismaTakip

final class AppTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "windows-protocol", withExtension: "json", subdirectory: "Fixtures"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    func testWindowsEnrollmentAndSignatures() throws {
        let f = try fixture(), code = try XCTUnwrap(f["code"] as? String)
        let packet = try XCTUnwrap(f["packet"] as? [String: Any])
        let key = try Crypto.open(packet, code: code)
        XCTAssertEqual(key.base64EncodedString(), f["key"] as? String)
        for (field, expected) in [("body", "signature"), ("path", "getSignature")] {
            let signature = Crypto.signature(key: key, timestamp: try XCTUnwrap(f["timestamp"] as? String), body: Data(try XCTUnwrap(f[field] as? String).utf8))
            XCTAssertEqual(signature, f[expected] as? String)
        }
    }
    func testWrongCodeAndTamperingRejected() throws {
        let f = try fixture(), code = try XCTUnwrap(f["code"] as? String)
        var packet = try XCTUnwrap(f["packet"] as? [String: Any])
        XCTAssertThrowsError(try Crypto.open(packet, code: "WRONGCODE123"))
        var ciphertext = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(packet["veri"] as? String)))
        ciphertext[0] ^= 1; packet["veri"] = ciphertext.base64EncodedString()
        XCTAssertThrowsError(try Crypto.open(packet, code: code))
    }
    func testBackupRoundTripAndTamperProtection() async throws {
        try await MainActor.run {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("ct-test-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let storage = try Storage(root: root)
            var state = TrackerState(); state.settings.targetMinutes = 120
            state.rules.calisma.surec = ["TestEditor"]; state.days["2026-09-16"] = Day(date: "2026-09-16")
            try storage.append(Sample(app: "TestEditor"), seconds: 10, category: .work)
            let url = try storage.backup(state)
            let backup = try storage.inspectBackup(url)
            XCTAssertEqual(backup.rules.calisma.surec, ["TestEditor"])
            state.settings.targetMinutes = 999
            let (restored, safety) = try storage.restore(backup, current: state)
            XCTAssertEqual(restored.settings.targetMinutes, 120)
            XCTAssertTrue(FileManager.default.fileExists(atPath: safety.path))
            var envelope = try storage.decoder.decode(Storage.Envelope.self, from: Data(contentsOf: url))
            envelope.payload.append(0)
            try storage.encoder.encode(envelope).write(to: url)
            XCTAssertThrowsError(try storage.inspectBackup(url))
        }
    }
    func testBackupTraversalRejectedEvenWithValidHash() async throws {
        try await MainActor.run {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("ct-test-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let storage = try Storage(root: root)
            let backup = Storage.Backup(created: Date(), settings: Settings(), rules: Rules(), days: [:], activity: ["../outside.csv": Data()])
            let payload = try storage.encoder.encode(backup)
            let envelope = Storage.Envelope(payload: payload, sha256: Storage.hash(payload))
            let file = root.appendingPathComponent("bad.ctbackup")
            try storage.encoder.encode(envelope).write(to: file)
            XCTAssertThrowsError(try storage.inspectBackup(file))
        }
    }
    func testDuplicateInstanceAndCorruptStateAreRejected() async throws {
        try await MainActor.run {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("ct-test-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let storage = try Storage(root: root)
            XCTAssertThrowsError(try Storage(root: root))
            let data = Data("invalid-json".utf8), file = root.appendingPathComponent("state.json")
            try data.write(to: file)
            XCTAssertThrowsError(try storage.load("state.json", default: TrackerState()))
            XCTAssertEqual(try Data(contentsOf: file), data)
        }
    }
    func testCenterEnrollmentAuthenticationPermissionsAndReEnrollment() async throws {
        try await MainActor.run {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("ct-test-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let storage = try Storage(root: root)
            var keys: [String: Data] = [:]
            let credentials = CenterCredentials(read: { account in
                guard let key = keys[account] else { throw AppError.message("Test key absent") }; return key
            }, write: { keys[$1] = $0 }, remove: { keys[$0] = nil })
            let center = try Center(storage: storage, credentials: credentials)
            let code = try center.code(name: "Windows test device")
            let enrollmentBody = try Wire.json(["schemaVersion": 1, "kod": code, "onay": true])
            let enrollment = IncomingRequest(method: "POST", target: "/v1/kayit", headers: [:], body: enrollmentBody)
            let response = center.handle(enrollment)
            XCTAssertEqual(response.status, 200)
            let id = try XCTUnwrap(response.json["cihazId"] as? String)
            let key = try Crypto.open(try XCTUnwrap(response.json["anahtar"] as? [String: Any]), code: code)
            XCTAssertEqual(center.handle(enrollment).status, 403, "Single use code")
            func signed(_ path: String, _ body: Data? = nil, key: Data, timestamp: String = String(Int(Date().timeIntervalSince1970))) -> IncomingRequest {
                IncomingRequest(method: body == nil ? "GET" : "POST", target: path, headers: [
                    "x-ct-cihaz": id, "x-ct-zaman": timestamp,
                    "x-ct-imza": Crypto.signature(key: key, timestamp: timestamp, body: body ?? Data(path.utf8))
                ], body: body ?? Data())
            }
            XCTAssertEqual(center.handle(signed("/v1/kurallar", key: Data(repeating: 0, count: 32))).status, 401)
            XCTAssertEqual(center.handle(signed("/v1/kurallar", key: key, timestamp: "1")).status, 401)
            let ruleBody = try Wire.json(["schemaVersion": 1, "cihazId": id, "kararlar": [["oge": "Editor", "tur": "surec", "karar": "calisma"]]])
            XCTAssertEqual(center.handle(signed("/v1/kural", ruleBody, key: key)).status, 403)
            var device = try XCTUnwrap(center.state.devices.first); device.canWriteRules = true
            try center.updateDevice(device)
            XCTAssertEqual(center.handle(signed("/v1/kural", ruleBody, key: key)).status, 200)
            XCTAssertEqual(center.state.rules.calisma.surec, ["Editor"])
            var connection = Connection(server: "http://localhost:8787", deviceID: id, deviceName: "Test", consentAt: Date())
            var day = Day(date: dayKey(Date())); day.workSeconds = 600
            connection.sequence = 50
            let body = try Wire.json(Wire.body(day: day, connection: connection, target: 240, pending: 0, now: Date()))
            XCTAssertEqual(center.handle(signed("/v1/ozet", body, key: key)).status, 200)
            let total = center.handle(signed("/v1/toplam?tarih=" + day.date, key: key))
            XCTAssertEqual(total.json["toplamDk"] as? Int, 10)
            XCTAssertEqual(total.json["digerCihazDk"] as? Int, 0)
            connection.sequence = 1; day.workSeconds = 60
            let stale = try Wire.json(Wire.body(day: day, connection: connection, target: 240, pending: 0, now: Date()))
            _ = center.handle(signed("/v1/ozet", stale, key: key))
            XCTAssertEqual(center.total(day: day.date), 10, "Old sequence must not overwrite")
            let newCode = try center.code(name: device.name, deviceID: id)
            let renewed = center.handle(IncomingRequest(method: "POST", target: "/v1/kayit", headers: [:], body: try Wire.json(["schemaVersion": 1, "kod": newCode, "onay": true])))
            let newKey = try Crypto.open(try XCTUnwrap(renewed.json["anahtar"] as? [String: Any]), code: newCode)
            XCTAssertEqual(center.handle(signed("/v1/kurallar", key: key)).status, 401, "Old key must be invalidated")
            XCTAssertEqual(center.handle(signed("/v1/ozet", stale, key: newKey)).status, 200)
            XCTAssertEqual(center.total(day: day.date), 1, "New enrollment must reset sequence epoch")
            device.active = false; try center.updateDevice(device)
            XCTAssertEqual(center.handle(signed("/v1/kurallar", key: newKey)).status, 401)
        }
    }
    /// Protokol v2: internetten şifreli kayıt ve gönderim, tekrar koruması; v1 uçları yalnız yerel ağda.
    func testCenterV2EnvelopeFlowAndLocalOnlyV1() async throws {
        try await MainActor.run {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("ct-test-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let storage = try Storage(root: root)
            var keys: [String: Data] = [:]
            let credentials = CenterCredentials(read: { account in
                guard let key = keys[account] else { throw AppError.message("Test key absent") }; return key
            }, write: { keys[$1] = $0 }, remove: { keys[$0] = nil })
            let center = try Center(storage: storage, credentials: credentials)
            try center.setInternetURL("http://aizen.example.test:8787")
            let internet = "203.0.113.9"
            func post(_ envelope: [String: Any]) throws -> ServerResponse {
                let body = try Wire.json(envelope)
                return center.handle(IncomingRequest(method: "POST", target: "/v2/zarf", headers: [:], body: body, remote: "203.0.113.9"))
            }

            let code = try center.code(name: "Uzak Mac")
            let enrollment = try Zarf.enrollment(code: code)
            XCTAssertEqual(center.state.devices.first?.channel, enrollment.channel)
            let wrong = try Zarf.enrollment(code: "ZZZZ-ZZZZ-ZZZZ")
            let wrongRequest = try Zarf.seal(Data("{}".utf8), keys: wrong.keys, device: wrong.channel, kind: "kayit", direction: "istek", sequence: 1)
            XCTAssertEqual(try post(wrongRequest).status, 403)

            let requestBody = try Wire.json(["schemaVersion": 2, "onay": true, "cihazAdi": "Uzak", "kullanici": "test", "surum": "mac-2.0"])
            let request = try Zarf.seal(requestBody, keys: enrollment.keys, device: enrollment.channel, kind: "kayit", direction: "istek", sequence: 1)
            let response = try post(request)
            XCTAssertEqual(response.status, 200, "v2 kayıt reddedildi: \(response.json)")
            let reply = try Client.openReply(response.json, keys: enrollment.keys)
            XCTAssertEqual(reply.status, 200)
            let id = try XCTUnwrap(reply.body["cihazId"] as? String)
            let key = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(reply.body["anahtar"] as? String)))
            XCTAssertEqual(reply.body["ekAdresler"] as? [String], ["http://aizen.example.test:8787"])
            XCTAssertEqual(try post(request).status, 403, "Kod tek kullanımlık")
            let legacy = IncomingRequest(method: "POST", target: "/v1/kayit", headers: [:], body: try Wire.json(["schemaVersion": 1, "kod": code, "onay": true]), remote: "192.168.1.9")
            XCTAssertEqual(center.handle(legacy).status, 403, "v2 ile kullanılan kod v1'de de geçersiz")

            let deviceKeys = Zarf.keys(deviceKey: key)
            var connection = Connection(server: "http://203.0.113.1:8787", deviceID: id, deviceName: "Uzak", consentAt: Date())
            connection.sequence = 1
            var day = Day(date: dayKey(Date())); day.workSeconds = 900
            let summaryBody = try Wire.json(Wire.body(day: day, connection: connection, target: 240, pending: 0, now: Date()))
            let summary = try post(try Zarf.seal(summaryBody, keys: deviceKeys, device: id, kind: "ozet", direction: "istek", sequence: 1))
            XCTAssertEqual(summary.status, 200)
            let summaryReply = try Client.openReply(summary.json, keys: deviceKeys)
            XCTAssertEqual(summaryReply.status, 200)
            XCTAssertNotNil(summaryReply.addresses, "Yanıt güncel adresleri taşır")
            XCTAssertEqual(center.total(day: day.date), 15)

            let ruleBody = try Wire.json(["schemaVersion": 1, "cihazId": id, "kararlar": [["oge": "Editor", "tur": "surec", "karar": "calisma"]]])
            let denied = try post(try Zarf.seal(ruleBody, keys: deviceKeys, device: id, kind: "kural", direction: "istek", sequence: 10))
            XCTAssertEqual(try Client.openReply(denied.json, keys: deviceKeys).status, 403, "İzinsiz kural yazımı zarfın içinde 403")
            var device = try XCTUnwrap(center.state.devices.first(where: { $0.id == id }))
            device.canWriteRules = true
            try center.updateDevice(device)
            let rule = try Zarf.seal(ruleBody, keys: deviceKeys, device: id, kind: "kural", direction: "istek", sequence: 5000)
            let accepted = try post(rule)
            XCTAssertEqual(accepted.status, 200)
            XCTAssertEqual(try Client.openReply(accepted.json, keys: deviceKeys).body["islenen"] as? Int, 1)
            XCTAssertEqual(try post(rule).status, 409, "Aynı kural zarfı tekrar işlenmez")
            XCTAssertEqual(try post(try Zarf.seal(ruleBody, keys: deviceKeys, device: id, kind: "kural", direction: "istek", sequence: 3000)).status, 409, "Pencerenin gerisindeki sayaç")
            XCTAssertEqual(try post(try Zarf.seal(ruleBody, keys: deviceKeys, device: id, kind: "kural", direction: "istek", sequence: 4990)).status, 200, "Pencere içinde geç gelen zarf")
            var tampered = rule
            tampered["sayac"] = 5001
            XCTAssertEqual(try post(tampered).status, 401)
            let old = try Zarf.seal(Data("{}".utf8), keys: deviceKeys, device: id, kind: "kurallar", direction: "istek", sequence: 6000, time: Int64(Date().timeIntervalSince1970) - 31 * 86400)
            XCTAssertEqual(try post(old).status, 401, "30 günden eski zarf")

            let timestamp = String(Int(Date().timeIntervalSince1970))
            let headers = ["x-ct-cihaz": id, "x-ct-zaman": timestamp, "x-ct-imza": Crypto.signature(key: key, timestamp: timestamp, body: Data("/v1/kurallar".utf8))]
            XCTAssertEqual(center.handle(IncomingRequest(method: "GET", target: "/v1/kurallar", headers: headers, body: Data(), remote: internet)).status, 403, "v1 internete kapalı")
            XCTAssertEqual(center.handle(IncomingRequest(method: "GET", target: "/v1/kurallar", headers: headers, body: Data(), remote: "192.168.1.9")).status, 200, "v1 yerel ağda açık")
            XCTAssertEqual(center.handle(IncomingRequest(method: "GET", target: "/health", headers: [:], body: Data(), remote: internet)).json["protokol"] as? Int, 2)
        }
    }
    func testLocalAddressClassificationMatchesWindows() {
        for local in ["127.0.0.1", "10.1.2.3", "172.16.0.1", "172.31.255.1", "192.168.1.5", "100.100.1.1", "169.254.3.4", "::1", "fd12::1", "fe80::1%en0", "::ffff:192.168.1.9"] {
            XCTAssertTrue(Center.isLocal(local), local)
        }
        for remote in ["172.32.0.1", "100.128.0.1", "8.8.8.8", "203.0.113.9", "2001:4860::8888", "", "example.com"] {
            XCTAssertFalse(Center.isLocal(remote), remote)
        }
    }
}

import Foundation
import TakipCore

final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct HTTPFailure: LocalizedError {
    var status: Int
    var errorDescription: String? {
        switch status {
        case 401: return "Cihaz anahtarı kabul edilmedi (401)."
        case 403: return "Kod geçersiz veya cihaz yetkisi yok (403)."
        case 409: return "Merkez bu isteği daha önce işledi (409)."
        case 429: return "İstek sınırı aşıldı; daha sonra tekrar deneyin (429)."
        default: return "Merkez HTTP \(status) döndürdü."
        }
    }
}
/// Şifreli yanıt zarfının içi: `kod` (v1 HTTP durumu), `govde` ve merkezin güncel adresleri.
struct EnvelopeReply {
    var status: Int
    var body: [String: Any]
    var addresses: [String: Any]?
    /// Merkezin yanıtı ürettiği an (Unix sn); posta kutusunda bekleyen yanıtın tazeliği buradan ölçülür
    var time: Int64
}
struct MailboxReply {
    var kind: String
    var sequence: Int64
    var reply: EnvelopeReply
}
final class Client {
    private let delegate = RedirectBlocker()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 30
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()
    static func serverURL(_ text: String) throws -> URL {
        guard let c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), ["http", "https"].contains(c.scheme?.lowercased() ?? ""), c.host != nil, c.user == nil, c.password == nil, c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/", let url = c.url else { throw AppError.message("Merkez adresi http://sunucu:8787 veya https://sunucu biçiminde olmalı.") }
        return url
    }
    func request(server: String, path: String, body: Data? = nil, connection: Connection? = nil) async throws -> Data {
        let base = try Self.serverURL(server)
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL, url.host == base.host else { throw AppError.message("İstek adresi geçersiz.") }
        var request = URLRequest(url: url); request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if let connection {
            let timestamp = String(Int(Date().timeIntervalSince1970))
            let key = try Secrets.get("client:" + connection.deviceID)
            request.setValue(connection.deviceID, forHTTPHeaderField: "X-CT-Cihaz")
            request.setValue(timestamp, forHTTPHeaderField: "X-CT-Zaman")
            request.setValue(Crypto.signature(key: key, timestamp: timestamp, body: body ?? Data(path.utf8)), forHTTPHeaderField: "X-CT-Imza")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw HTTPFailure(status: (response as? HTTPURLResponse)?.statusCode ?? 0) }
        guard data.count <= 2 * 1024 * 1024 else { throw AppError.message("Merkez yanıtı boyut sınırını aşıyor.") }
        return data
    }
    /// v2 ve posta kutusu istekleri: tam adres, isteğe bağlı başlıklar, 2xx dışı HTTPFailure.
    func send(_ address: String, method: String = "POST", body: Data?, headers: [String: String] = [:], timeout: TimeInterval = 20) async throws -> Data {
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw AppError.message("İstek adresi geçersiz.") }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HTTPFailure(status: 0) }
        guard (200..<300).contains(http.statusCode) else { throw HTTPFailure(status: http.statusCode) }
        guard data.count <= 8 * 1024 * 1024 else { throw AppError.message("Yanıt boyut sınırını aşıyor.") }
        return data
    }

    // MARK: Kayıt

    func enroll(server: String, code: String, name: String) async throws -> Connection {
        let normal = Wire.normalizedCode(code)
        guard (8...32).contains(normal.count) else { throw AppError.message("Eşleşme kodu 8–32 karakter olmalı.") }
        guard let address = CenterAddress.parse(server) else { throw AppError.message("Merkez adresi http://sunucu:8787 ya da https://posta-sunucusu/k/kutu biçiminde olmalı.") }
        if address.kind == .mailbox, !address.isSecureTransport { throw AppError.message("Posta kutusu adresi https:// ile başlamalı.") }
        if let connection = try await enrollV2(address: address, code: normal, name: name) { return connection }
        return try await enrollV1(server: address.root, code: normal, name: name)
    }
    /// Yalnızca v1 bilen eski merkez (doğrudan adreste /v2/zarf 404). Kod bu istekte düz gider.
    private func enrollV1(server: String, code normal: String, name: String) async throws -> Connection {
        let base = try Self.serverURL(server).absoluteString
        let body = try Wire.json(["schemaVersion": 1, "kod": normal, "cihazAdi": String(name.prefix(80)), "kullanici": NSUserName(), "surum": "mac-1.0", "onay": true])
        let data = try await request(server: base, path: "/v1/kayit", body: body)
        guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any], reply["ok"] as? Bool == true, let id = reply["cihazId"] as? String, id.range(of: #"^[A-Za-z0-9_-]{3,64}$"#, options: .regularExpression) != nil, let packet = reply["anahtar"] as? [String: Any] else { throw AppError.message("Merkez kaydı yanıtı geçersiz.") }
        let key = try Crypto.open(packet, code: normal)
        try Secrets.set(key, account: "client:" + id)
        return Connection(server: base, deviceID: id, deviceName: String((reply["cihazAdi"] as? String ?? name).prefix(80)), consentAt: Date())
    }
    /// v2: kod ağa çıkmaz; istek ve yanıt koddan türetilen anahtarla şifrelidir. Eski merkezde nil döner.
    private func enrollV2(address: CenterAddress, code: String, name: String) async throws -> Connection? {
        let enrollment = try Zarf.enrollment(code: code)
        let requestBody = try Wire.json(["schemaVersion": 2, "onay": true, "cihazAdi": String(name.prefix(80)), "kullanici": NSUserName(), "surum": "mac-2.0"])
        let envelope = try Zarf.seal(requestBody, keys: enrollment.keys, device: enrollment.channel, kind: "kayit", direction: "istek", sequence: 1)
        var replies: [[String: Any]] = []
        if address.kind == .direct {
            do {
                let data = try await send(address.root + "/v2/zarf", body: try Wire.json(envelope))
                if let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any] { replies = [reply] }
            } catch let failure as HTTPFailure {
                switch failure.status {
                case 404: return nil
                case 403: throw AppError.message("Kod geçersiz, süresi dolmuş veya kullanılmış. Yöneticiden yeni kod isteyin.")
                case 401: throw AppError.message("Merkez isteği reddetti: bu Mac'in saati yanlış olabilir.")
                default: throw failure
                }
            }
        } else {
            replies = try await mailboxEnrollment(address, enrollment: enrollment, envelope: envelope)
        }
        // Önceki denemenin başarılı yanıtı kutuda kaldıysa o seçilir
        var chosen: [String: Any]?
        for reply in replies {
            guard reply["cihaz"] as? String == enrollment.channel, reply["tur"] as? String == "kayit", reply["yon"] as? String == "yanit",
                  let plain = try? Zarf.open(reply, keys: enrollment.keys),
                  let object = try? JSONSerialization.jsonObject(with: plain) as? [String: Any] else { continue }
            if chosen == nil || object["kod"] as? Int == 200 { chosen = object }
        }
        guard let result = chosen else { throw AppError.message("Merkezin yanıtı doğrulanamadı: kod yanlış olabilir ya da yanıt yolda değiştirilmiş.") }
        switch result["kod"] as? Int ?? 0 {
        case 200: break
        case 403: throw AppError.message("Kod geçersiz, süresi dolmuş veya kullanılmış. Yöneticiden yeni kod isteyin.")
        case 400: throw AppError.message("Merkez isteği reddetti (biçim veya onay hatası).")
        default: throw AppError.message("Merkez kaydı tamamlayamadı.")
        }
        guard let body = result["govde"] as? [String: Any], body["ok"] as? Bool == true, let id = body["cihazId"] as? String,
              Zarf.isDeviceID(id), !Zarf.isChannel(id), let keyText = body["anahtar"] as? String,
              let key = Data(base64Encoded: keyText), key.count == 32 else { throw AppError.message("Merkez kaydı yanıtı geçersiz.") }
        try Secrets.set(key, account: "client:" + id)
        var connection = Connection(server: address.text, deviceID: id, deviceName: String((body["cihazAdi"] as? String ?? name).prefix(80)), consentAt: Date())
        connection.protocolVersion = 2
        connection.counter = 0
        let merged = CenterAddress.merge(reported: body, direct: address.kind == .direct ? [address.text] : [],
                                         mailbox: address.kind == .mailbox ? address.text : nil, used: address.kind == .direct ? address.text : nil)
        connection.directAddresses = merged.direct
        connection.mailbox = merged.mailbox
        return connection
    }
    private func mailboxEnrollment(_ address: CenterAddress, enrollment: Zarf.Enrollment, envelope: [String: Any]) async throws -> [[String: Any]] {
        let headers = Self.mailboxHeaders(address, device: enrollment.channel, token: enrollment.keys.mailboxToken)
        let body = try Wire.json(["anahtar": "", "zarf": envelope])
        let deadline = Date().addingTimeInterval(150)
        // Merkez yeni kodun kanalını kutuya birkaç saniyede bildirir; o zamana kadar 401 döner.
        while true {
            do {
                _ = try await send(address.root + "/r1/cihaz/gonder", body: body, headers: headers)
                break
            } catch let failure as HTTPFailure where failure.status == 401 {
                guard Date() < deadline else { throw AppError.message("Kod geçersiz ya da merkez bilgisayarı şu anda kapalı. Merkez açıkken tekrar deneyin.") }
                try await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
        while Date() < deadline {
            if let data = try? await send(address.root + "/r1/cihaz/gelen", method: "GET", body: nil, headers: headers),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let messages = object["mesajlar"] as? [[String: Any]], !messages.isEmpty {
                let numbers = messages.compactMap { ($0["no"] as? NSNumber)?.int64Value }
                if let ack = try? Wire.json(["nolar": numbers]) { _ = try? await send(address.root + "/r1/cihaz/onay", body: ack, headers: headers) }
                let replies = messages.compactMap { $0["zarf"] as? [String: Any] }.filter { $0["tur"] as? String == "kayit" && $0["yon"] as? String == "yanit" }
                if !replies.isEmpty { return replies }
            }
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
        throw AppError.message("Merkez yanıt vermedi. Merkez bilgisayarı açıkken tekrar deneyin; kod 30 dakika içinde yeniden kullanılabilir.")
    }

    // MARK: v2 gönderim

    static func mailboxHeaders(_ mailbox: CenterAddress, device: String, token: String) -> [String: String] {
        ["X-Aizen-Kutu": mailbox.box, "X-Aizen-Cihaz": device, "X-Aizen-Jeton": token]
    }
    static func openReply(_ envelope: [String: Any], keys: ZarfKeys) throws -> EnvelopeReply {
        let plain = try Zarf.open(envelope, keys: keys)
        guard let object = try JSONSerialization.jsonObject(with: plain) as? [String: Any], let status = object["kod"] as? Int else { throw AppError.message("Merkez yanıtı okunamadı.") }
        return EnvelopeReply(status: status, body: object["govde"] as? [String: Any] ?? [:], addresses: object["adresler"] as? [String: Any],
                             time: (envelope["zaman"] as? NSNumber)?.int64Value ?? 0)
    }
    /// Doğrudan adres v2 konuşuyor mu (kısa zaman aşımı: ofis dışındayken yerel adres beklenmez).
    func isV2Center(_ root: String) async -> Bool {
        guard let address = CenterAddress.parse(root), address.kind == .direct,
              let data = try? await send(address.root + "/health", method: "GET", body: nil, timeout: 4),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["ok"] as? Bool == true && (object["protokol"] as? Int ?? 1) >= 2
    }
    func direct(root: String, keys: ZarfKeys, device: String, kind: String, sequence: Int64, plain: Data) async throws -> EnvelopeReply {
        let envelope = try Zarf.seal(plain, keys: keys, device: device, kind: kind, direction: "istek", sequence: sequence)
        let data = try await send(root + "/v2/zarf", body: try Wire.json(envelope))
        guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any], reply["cihaz"] as? String == device,
              reply["tur"] as? String == kind, reply["yon"] as? String == "yanit",
              (reply["sayac"] as? NSNumber)?.int64Value == sequence else { throw AppError.message("Merkez yanıtı bu isteğe ait değil.") }
        return try Self.openReply(reply, keys: keys)
    }
    func mailboxPost(_ mailbox: CenterAddress, keys: ZarfKeys, device: String, kind: String, sequence: Int64, plain: Data, coalesce: String) async throws {
        let envelope = try Zarf.seal(plain, keys: keys, device: device, kind: kind, direction: "istek", sequence: sequence)
        let body = try Wire.json(["anahtar": coalesce, "zarf": envelope])
        _ = try await send(mailbox.root + "/r1/cihaz/gonder", body: body, headers: Self.mailboxHeaders(mailbox, device: device, token: keys.mailboxToken))
    }
    /// Kutudaki yanıtları alır, doğrulananları sayaç sırasıyla döndürür ve hepsini onaylar.
    func mailboxReplies(_ mailbox: CenterAddress, keys: ZarfKeys, device: String) async throws -> [MailboxReply] {
        let headers = Self.mailboxHeaders(mailbox, device: device, token: keys.mailboxToken)
        let data = try await send(mailbox.root + "/r1/cihaz/gelen", method: "GET", body: nil, headers: headers)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AppError.message("Posta kutusu yanıtı okunamadı.") }
        let messages = object["mesajlar"] as? [[String: Any]] ?? []
        var result: [MailboxReply] = []
        var numbers: [Int64] = []
        for message in messages {
            if let number = (message["no"] as? NSNumber)?.int64Value { numbers.append(number) }
            guard let envelope = message["zarf"] as? [String: Any], envelope["cihaz"] as? String == device, envelope["yon"] as? String == "yanit",
                  let kind = envelope["tur"] as? String, let sequence = (envelope["sayac"] as? NSNumber)?.int64Value,
                  let reply = try? Self.openReply(envelope, keys: keys) else { continue }
            result.append(MailboxReply(kind: kind, sequence: sequence, reply: reply))
        }
        if !numbers.isEmpty { _ = try await send(mailbox.root + "/r1/cihaz/onay", body: try Wire.json(["nolar": numbers]), headers: headers) }
        return result.sorted { $0.sequence < $1.sequence }
    }
}

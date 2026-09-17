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
        case 429: return "İstek sınırı aşıldı; daha sonra tekrar deneyin (429)."
        default: return "Merkez HTTP \(status) döndürdü."
        }
    }
}
final class Client {
    private let delegate = RedirectBlocker()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
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
    func enroll(server: String, code: String, name: String) async throws -> Connection {
        let normal = Wire.normalizedCode(code)
        guard (8...32).contains(normal.count) else { throw AppError.message("Eşleşme kodu 8–32 karakter olmalı.") }
        let base = try Self.serverURL(server).absoluteString
        let body = try Wire.json(["schemaVersion": 1, "kod": normal, "cihazAdi": String(name.prefix(80)), "kullanici": NSUserName(), "surum": "mac-1.0", "onay": true])
        let data = try await request(server: base, path: "/v1/kayit", body: body)
        guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any], reply["ok"] as? Bool == true, let id = reply["cihazId"] as? String, id.range(of: #"^[A-Za-z0-9_-]{3,64}$"#, options: .regularExpression) != nil, let packet = reply["anahtar"] as? [String: Any] else { throw AppError.message("Merkez kaydı yanıtı geçersiz.") }
        let key = try Crypto.open(packet, code: normal)
        try Secrets.set(key, account: "client:" + id)
        return Connection(server: base, deviceID: id, deviceName: String((reply["cihazAdi"] as? String ?? name).prefix(80)), consentAt: Date())
    }
}

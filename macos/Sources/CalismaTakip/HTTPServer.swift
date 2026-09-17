import Foundation
import Network

struct IncomingRequest {
    var method: String
    var target: String
    var headers: [String: String]
    var body: Data
}
struct ServerResponse {
    var status: Int = 200
    var json: [String: Any]
    static func error(_ status: Int, _ text: String) -> ServerResponse { ServerResponse(status: status, json: ["ok": false, "hata": text]) }
}
final class HTTPServer {
    private let queue = DispatchQueue(label: "local.calisma-takip.http")
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    var handler: (@MainActor (IncomingRequest) -> ServerResponse)?
    var statusChanged: (@MainActor (String) -> Void)?
    func start(port: UInt16, lan: Bool) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(lan ? "0.0.0.0" : "127.0.0.1"), port: NWEndpoint.Port(rawValue: port)!)
        let service = try NWListener(using: params)
        service.stateUpdateHandler = { [weak self] state in
            let message: String
            switch state {
            case .ready: message = "Merkez çalışıyor · \(lan ? "Yerel ağ" : "Yalnız bu Mac") · port \(port)"
            case .failed: message = "Merkez başlatılamadı; port kullanımda veya ağ izni kapalı."
            case .cancelled: message = "Merkez kapalı"
            default: return
            }
            Task { @MainActor in self?.statusChanged?(message) }
        }
        service.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener = service; service.start(queue: queue)
    }
    func stop() {
        listener?.cancel(); listener = nil
        queue.async { [weak self] in
            self?.connections.values.forEach { $0.cancel() }; self?.connections.removeAll()
        }
    }
    private func accept(_ connection: NWConnection) {
        guard connections.count < 32 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { self?.connections[id] = nil }
            if case .failed = state { self?.connections[id] = nil }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 20) { [weak self, weak connection] in
            connection?.cancel(); self?.connections[id] = nil
        }
        read(connection, buffer: Data(), sentContinue: false)
    }
    private func send(_ response: ServerResponse, to connection: NWConnection) {
        let body = (try? JSONSerialization.data(withJSONObject: response.json, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{\"ok\":false}".utf8)
        let header = "HTTP/1.1 \(response.status) Result\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
    private func read(_ connection: NWConnection, buffer: Data, sentContinue: Bool) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, complete, error in
            guard let self else { connection.cancel(); return }
            var bytes = buffer; bytes.append(chunk ?? Data())
            if bytes.count > 600 * 1024 { self.send(.error(413, "Paket çok büyük."), to: connection); return }
            guard let marker = bytes.range(of: Data("\r\n\r\n".utf8)) else {
                if bytes.count > 32768 || complete || error != nil { self.send(.error(400, "HTTP başlığı geçersiz."), to: connection) }
                else { self.read(connection, buffer: bytes, sentContinue: sentContinue) }
                return
            }
            guard marker.lowerBound <= 32768, let head = String(data: bytes.prefix(upTo: marker.lowerBound), encoding: .utf8) else { self.send(.error(400, "Başlık okunamadı."), to: connection); return }
            let lines = head.components(separatedBy: "\r\n")
            let first = (lines.first ?? "").split(separator: " ")
            guard first.count == 3, ["GET", "POST"].contains(String(first[0])), first[1].hasPrefix("/"), first[2] == "HTTP/1.1" else { self.send(.error(400, "İstek satırı geçersiz."), to: connection); return }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { self.send(.error(400, "Başlık geçersiz."), to: connection); return }
                let key = line[..<colon].lowercased(), value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                guard headers[key] == nil else { self.send(.error(400, "Yinelenen başlık."), to: connection); return }
                headers[key] = value
            }
            guard headers["transfer-encoding"] == nil, let length = Int(headers["content-length"] ?? "0"), (0...524288).contains(length) else { self.send(.error(400, "Content-Length gerekli; parça aktarımı desteklenmiyor."), to: connection); return }
            let available = bytes.count - marker.upperBound
            if available < length {
                if complete || error != nil { self.send(.error(400, "Eksik gövde."), to: connection); return }
                var continued = sentContinue
                if headers["expect"]?.lowercased() == "100-continue", !continued {
                    connection.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .contentProcessed { _ in }); continued = true
                }
                self.read(connection, buffer: bytes, sentContinue: continued); return
            }
            guard available == length else { self.send(.error(400, "İstek uzunluğu geçersiz."), to: connection); return }
            let request = IncomingRequest(method: String(first[0]), target: String(first[1]), headers: headers, body: Data(bytes.suffix(length)))
            Task { @MainActor in
                let response = self.handler?(request) ?? .error(503, "Merkez hazır değil.")
                self.queue.async { self.send(response, to: connection) }
            }
        }
    }
}

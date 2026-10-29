import Foundation

public struct HTTPResponse {
    public let status: Int
    public let contentType: String
    public let body: Data
    public let filename: String?

    public init(status: Int, contentType: String, body: Data, filename: String? = nil) {
        self.status = status
        self.contentType = contentType
        self.body = body
        self.filename = filename
    }

    public var reason: String {
        [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large"][status] ?? "OK"
    }

    /// Full HTTP/1.1 response; every response closes the connection.
    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n"
        if let filename { head += "Content-Disposition: attachment; filename=\"\(filename)\"\r\n" }
        head += "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

public struct HTTPRequest {
    public let method: String
    public let target: String
    public let headers: [String: String]   // lowercase names
    public let body: Data
    /// True only when the connection comes from this Mac (loopback); writes are refused otherwise.
    public let isLocal: Bool

    public init(method: String, target: String, headers: [String: String] = [:], body: Data = Data(), isLocal: Bool = false) {
        self.method = method
        self.target = target
        self.headers = headers
        self.body = body
        self.isLocal = isLocal
    }
}

public enum DashboardRouter {
    public static let maxBody = 32 * 1024

    public static func respond(method: String, target: String, store: DashboardStore) -> HTTPResponse {
        respond(HTTPRequest(method: method, target: target), store: store)
    }

    public static func respond(_ request: HTTPRequest, store: DashboardStore) -> HTTPResponse {
        let method = request.method, target = request.target
        if method == "POST" { return post(request, store: store) }
        guard method == "GET" || method == "HEAD" else { return text(405, "Método não permitido") }
        guard let components = URLComponents(string: target) else { return text(400, "Requisição inválida") }
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        switch components.path {
        case "/", "/index.html":
            return HTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: Data(DashboardPage.html.utf8))
        case "/api/state":
            return jsonResponse(store.stateJSON())
        case "/api/history":
            let hours = min(max(Double(query["hours"] ?? "") ?? 12, 1), 24 * 30)
            return jsonResponse(store.historyJSON(hours: hours))
        case "/api/hunts":
            let limit = min(max(Int(query["limit"] ?? "") ?? 50, 1), 500)
            return jsonResponse(store.huntsJSON(limit: limit))
        case "/api/ranking":
            return jsonResponse(store.rankingJSON())
        case "/api/daily":
            return jsonResponse(store.dailyJSON(days: min(max(Int(query["days"] ?? "") ?? 14, 1), 30)))
        case "/api/presets":
            return jsonResponse(store.presetsJSON(canWrite: request.isLocal))
        case "/api/presets/compare":
            guard let id = Int(query["id"] ?? ""), let account = Int(query["account"] ?? "") else { return text(400, "Parâmetros inválidos") }
            return jsonResponse(store.presetComparison(id: id, account: account))
        case "/api/hunts/setup":
            guard let id = Int(query["id"] ?? "") else { return text(400, "Parâmetros inválidos") }
            return jsonResponse(store.huntSetup(id: id, compare: Int(query["compare"] ?? "")))
        case "/api/hunts.csv":
            return HTTPResponse(status: 200, contentType: "text/csv; charset=utf-8", body: store.huntsCSV(), filename: "tibidle-hunts.csv")
        case "/api/history.csv":
            let hours = min(max(Double(query["hours"] ?? "") ?? 24, 1), 24 * 30)
            return HTTPResponse(status: 200, contentType: "text/csv; charset=utf-8", body: store.historyCSV(hours: hours), filename: "tibidle-historico.csv")
        default:
            return text(404, "Não encontrado")
        }
    }

    /// The only writes: the local preset library. Loopback only, with a custom header (a web page on
    /// another origin cannot send it without a preflight, which this server never answers) and a Host check
    /// against DNS rebinding.
    private static func post(_ request: HTTPRequest, store: DashboardStore) -> HTTPResponse {
        let path = request.target.split(separator: "?").first.map(String.init) ?? ""
        guard path.hasPrefix("/api/presets/") else { return text(405, "Método não permitido") }
        let host = (request.headers["host"] ?? "").lowercased()
        let hostName = host.hasPrefix("[") ? String(host.prefix { $0 != "]" }) + "]" : String(host.split(separator: ":").first ?? "")
        guard request.isLocal, request.headers["x-tibidle"] == "1", ["localhost", "127.0.0.1", "[::1]"].contains(hostName),
              (request.headers["content-type"] ?? "").lowercased().hasPrefix("application/json") else {
            return text(403, "Escrita permitida somente neste Mac, pelo dashboard.")
        }
        guard request.body.count <= maxBody, let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] else {
            return text(400, "Corpo inválido")
        }
        func reply(_ result: Result<Int, DashboardStore.PresetError>) -> HTTPResponse {
            switch result {
            case .success(let id): return jsonResponse(Data(#"{"ok":true,"id":\#(id)}"#.utf8))
            case .failure(.message(let message)):
                let data = (try? JSONSerialization.data(withJSONObject: ["ok": false, "error": message])) ?? Data()
                return HTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: data)
            }
        }
        switch path {
        case "/api/presets/save":
            guard let account = body["account"] as? Int, let vocation = body["vocation"] as? String else { return text(400, "Parâmetros inválidos") }
            return reply(store.savePreset(account: account, vocation: vocation, name: body["name"] as? String))
        case "/api/presets/from-hunt":
            guard let id = body["id"] as? Int, let vocation = body["vocation"] as? String else { return text(400, "Parâmetros inválidos") }
            return reply(store.savePresetFromHunt(id: id, vocation: vocation, name: body["name"] as? String))
        case "/api/presets/import":
            guard let value = body["text"] as? String else { return text(400, "Parâmetros inválidos") }
            return reply(store.importPreset(text: value, name: body["name"] as? String))
        case "/api/presets/rename":
            guard let id = body["id"] as? Int, let name = body["name"] as? String else { return text(400, "Parâmetros inválidos") }
            return reply(store.renamePreset(id: id, name: name).map { id })
        case "/api/presets/delete":
            guard let id = body["id"] as? Int else { return text(400, "Parâmetros inválidos") }
            store.deletePreset(id: id)
            return reply(.success(id))
        default:
            return text(404, "Não encontrado")
        }
    }

    private static func jsonResponse(_ data: Data) -> HTTPResponse {
        HTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: data)
    }

    private static func text(_ status: Int, _ message: String) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "text/plain; charset=utf-8", body: Data(message.utf8))
    }
}

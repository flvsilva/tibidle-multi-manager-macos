import Foundation

public struct HTTPResponse {
    public let status: Int
    public let contentType: String
    public let body: Data

    public init(status: Int, contentType: String, body: Data) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }

    public var reason: String {
        [200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed"][status] ?? "OK"
    }

    /// Full HTTP/1.1 response; the dashboard is read-only, so every response closes the connection.
    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

public enum DashboardRouter {
    public static func respond(method: String, target: String, store: DashboardStore) -> HTTPResponse {
        guard method == "GET" || method == "HEAD" else { return text(405, "Somente leitura") }
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

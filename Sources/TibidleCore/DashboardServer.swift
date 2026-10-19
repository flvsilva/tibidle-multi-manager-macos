import Foundation
import Network

/// Minimal HTTP server for the dashboard, open to the local network. Reads are open; the only writes
/// (the preset library) are accepted from this Mac alone.
public final class DashboardServer {
    public static let preferredPort: UInt16 = 8787

    private let store: DashboardStore
    private let queue = DispatchQueue(label: "TibidleMultiManager.DashboardServer")
    private var listener: NWListener?
    public private(set) var port: UInt16?
    public var onReady: ((UInt16) -> Void)?

    public init(store: DashboardStore) { self.store = store }

    public func start(port: UInt16 = DashboardServer.preferredPort, attempts: Int = 10) {
        guard attempts > 0, let nwPort = NWEndpoint.Port(rawValue: port),
              let listener = try? NWListener(using: .tcp, on: nwPort) else { return }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                DispatchQueue.main.async { self?.port = port; self?.onReady?(port) }
            case .failed:
                listener.cancel()
                self?.queue.async { self?.start(port: port + 1, attempts: attempts - 1) }
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    public func stop() { listener?.cancel() }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 10) { connection.cancel() }
        receive(connection, buffer: Data())
    }

    private static func isLoopback(_ connection: NWConnection) -> Bool {
        guard case .hostPort(let host, _)? = Optional(connection.endpoint) else { return false }
        switch host {
        case .ipv4(let address): return address == IPv4Address.loopback
        case .ipv6(let address): return address == IPv6Address.loopback || address.isIPv4Mapped && address.asIPv4 == IPv4Address.loopback
        default: return false
        }
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, complete, error in
            guard let self, error == nil else { connection.cancel(); return }
            let buffer = buffer + (data ?? Data())
            guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if complete || buffer.count > 32 * 1024 { connection.cancel() } else { receive(connection, buffer: buffer) }
                return
            }
            let lines = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                if let colon = line.firstIndex(of: ":") {
                    headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
            }
            let length = Int(headers["content-length"] ?? "") ?? 0
            let bodyStart = end.upperBound
            if length > DashboardRouter.maxBody {
                connection.send(content: HTTPResponse(status: 413, contentType: "text/plain", body: Data()).serialized(),
                                completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            if buffer.count - bodyStart < length {
                if complete { connection.cancel() } else { receive(connection, buffer: buffer) }
                return
            }
            let parts = (lines.first ?? "").split(separator: " ")
            let response = parts.count >= 2
                ? DashboardRouter.respond(HTTPRequest(method: String(parts[0]), target: String(parts[1]), headers: headers,
                                                      body: buffer[bodyStart..<(bodyStart + length)], isLocal: Self.isLoopback(connection)),
                                          store: store)
                : HTTPResponse(status: 400, contentType: "text/plain", body: Data())
            var payload = response.serialized()
            if parts.first == "HEAD" { payload = payload.prefix(payload.count - response.body.count) }
            connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// Addresses other devices on the network can use to open the dashboard.
    public static func networkURLs(port: UInt16) -> [String] {
        var urls: [String] = []
        if let host = Host.current().localizedName?.replacingOccurrences(of: " ", with: "-"), !host.isEmpty {
            urls.append("http://\(host).local:\(port)")
        }
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return urls }
        defer { freeifaddrs(interfaces) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0, (interface.ifa_flags & UInt32(IFF_UP)) != 0,
                  String(cString: interface.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                urls.append("http://\(String(cString: host)):\(port)")
            }
        }
        return urls
    }
}

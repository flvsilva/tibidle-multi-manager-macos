import Foundation
import Network

/// Minimal HTTP server for the dashboard, open to the local network unless `localOnly`. Reads are open; the only
/// writes (the preset library, ignored advice) are accepted from this Mac alone.
public final class DashboardServer {
    public static let preferredPort: UInt16 = 8787
    /// A connection is closed after this long, even mid-transfer: generous for a phone on weak Wi-Fi.
    static let connectionTimeout: TimeInterval = 30

    private let store: DashboardStore
    private let queue = DispatchQueue(label: "TibidleMultiManager.DashboardServer")
    private var listener: NWListener?
    /// Only this Mac (loopback) may connect; set before `start` or through `restart(localOnly:)`.
    public private(set) var localOnly: Bool
    public private(set) var port: UInt16?
    public var onReady: ((UInt16) -> Void)?

    public init(store: DashboardStore, localOnly: Bool = false) {
        self.store = store
        self.localOnly = localOnly
    }

    public func start(port: UInt16 = DashboardServer.preferredPort, attempts: Int = 10) {
        let parameters = NWParameters.tcp
        // A quick relaunch finds the port still in TIME_WAIT: reuse it, so the phone's bookmark keeps working.
        parameters.allowLocalEndpointReuse = true
        if localOnly { parameters.requiredInterfaceType = .loopback }
        guard attempts > 0, let nwPort = NWEndpoint.Port(rawValue: port),
              let listener = try? NWListener(using: parameters, on: nwPort) else { return }
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

    /// Switches between this Mac only and the local network; the server comes back on the preferred port.
    public func restart(localOnly: Bool) {
        queue.async { [self] in
            self.localOnly = localOnly
            listener?.cancel()
            listener = nil
            start()
        }
    }

    private func serve(_ connection: NWConnection) {
        // The interface requirement already keeps the network out; this is the guarantee.
        if localOnly && !Self.isLoopback(connection) { connection.cancel(); return }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.connectionTimeout) { connection.cancel() }
        receive(connection, buffer: Data())
    }

    private func send(_ connection: NWConnection, _ response: HTTPResponse, headers: [String: String] = [:], head: Bool = false) {
        let gzip = (headers["accept-encoding"] ?? "").lowercased().contains("gzip")
        connection.send(content: response.serialized(gzip: gzip, includeBody: !head), completion: .contentProcessed { _ in connection.cancel() })
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
            var length = 0
            if let declared = headers["content-length"] {
                // A negative length would slice the buffer backwards: a crash any device on the network could cause.
                guard let parsed = Int(declared), parsed >= 0 else {
                    send(connection, HTTPResponse(status: 400, contentType: "text/plain", body: Data()))
                    return
                }
                length = parsed
            }
            let bodyStart = end.upperBound
            if length > DashboardRouter.maxBody {
                send(connection, HTTPResponse(status: 413, contentType: "text/plain", body: Data()))
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
            send(connection, response, headers: headers, head: parts.first == "HEAD")
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

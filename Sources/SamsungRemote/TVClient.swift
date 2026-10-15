import Foundation

/// Talks to a Tizen Samsung TV over the LAN (WebSocket API on port 8002).
@MainActor
final class TVClient: NSObject, ObservableObject {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    @Published var state: State = .disconnected
    @Published var ip: String { didSet { defaults.set(ip, forKey: "ip") } }
    @Published var tvName: String = ""
    @Published var discovered: [(ip: String, name: String)] = []
    @Published var scanning = false
    @Published var draft = ""  // text-entry field contents

    private let defaults = UserDefaults.standard
    private var token: String? { didSet { defaults.set(token, forKey: "token") } }
    private var mac: String? { didSet { defaults.set(mac, forKey: "mac") } }
    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    static let apps: [(name: String, id: String)] = [
        ("Netflix", "11101200001"),
        ("YouTube", "111299001912"),
        ("Prime Video", "3201512006785"),
        ("Disney+", "3201901017640"),
        ("Spotify", "3201606009684"),
        ("Apple TV", "3201807016597"),
    ]

    override init() {
        ip = UserDefaults.standard.string(forKey: "ip") ?? ""
        token = UserDefaults.standard.string(forKey: "token")
        mac = UserDefaults.standard.string(forKey: "mac")
        tvName = UserDefaults.standard.string(forKey: "name") ?? ""
        super.init()
        if !ip.isEmpty { Task { await connect() } }
    }

    // MARK: Connection

    func connect() async {
        let target = ip.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        disconnect()
        state = .connecting
        await fetchInfo(target)

        let name = Data("SamsungRemote".utf8).base64EncodedString()
        var urlString = "wss://\(target):8002/api/v2/channels/samsung.remote.control?name=\(name)"
        if let token { urlString += "&token=\(token)" }
        guard let url = URL(string: urlString) else { state = .failed("Invalid IP"); return }

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        do {
            // On first pairing the TV shows an "Allow" prompt; wait for the answer.
            // The TV may send other events (e.g. ms.remote.touchEnable) before ms.channel.connect.
            let obj = try await withTimeout(seconds: 40) { () -> [String: Any] in
                while true {
                    guard case .string(let text) = try await task.receive(),
                          let obj = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { continue }
                    switch obj["event"] as? String {
                    case "ms.channel.connect": return obj
                    case "ms.channel.unauthorized", "ms.channel.timeOut": throw TVDenied()
                    default: continue
                    }
                }
            }
            if let data = obj["data"] as? [String: Any], let t = data["token"] as? String { token = t }
            state = .connected
            listen(task)
        } catch is TVDenied {
            state = .failed("TV denied the connection. Allow it on the TV (or in Settings → Device Manager → External Device Manager → Device Connection Manager) and retry.")
            disconnect(keepState: true)
        } catch {
            state = .failed("Can't reach TV (\(error.localizedDescription)). Is it on, and on the same Wi-Fi?")
            disconnect(keepState: true)
        }
    }

    func disconnect(keepState: Bool = false) {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        if !keepState { state = .disconnected }
    }

    /// Drain incoming messages so we notice when the TV closes the socket.
    private func listen(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === task else { return }
                if case .failure = result {
                    self.task = nil
                    self.state = .disconnected
                } else {
                    self.listen(task)
                }
            }
        }
    }

    private func fetchInfo(_ ip: String) async {
        guard let url = URL(string: "http://\(ip):8001/api/v2/"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let device = obj["device"] as? [String: Any] else { return }
        if let m = device["wifiMac"] as? String { mac = m }
        let n = (device["name"] as? String) ?? (device["modelName"] as? String) ?? ""
        tvName = n
        defaults.set(n, forKey: "name")
    }

    // MARK: Commands

    func press(_ key: String) { send(["Cmd": "Click", "DataOfCmd": key, "Option": "false", "TypeOfRemote": "SendRemoteKey"]) }

    private func send(_ params: [String: String]) {
        transmit(["method": "ms.remote.control", "params": params])
    }

    /// Types into the TV's focused text field (the on-screen keyboard must be open).
    func sendText(_ text: String) {
        let b64 = Data(text.utf8).base64EncodedString()
        send(["Cmd": b64, "DataOfCmd": "base64", "TypeOfRemote": "SendInputString"])
    }

    func launch(appID: String) {
        transmit(["method": "ms.channel.emit", "params": [
            "event": "ed.apps.launch", "to": "host",
            "data": ["action_type": "DEEP_LINK", "appId": appID],
        ] as [String: Any]])
    }

    private func transmit(_ payload: [String: Any]) {
        guard state == .connected, let task,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            // Connection dropped (e.g. TV was off): reconnect, then resend.
            Task {
                await connect()
                if state == .connected { transmit(payload) }
            }
            return
        }
        task.send(.string(text)) { [weak self] error in
            if error != nil { Task { @MainActor in self?.state = .disconnected } }
        }
    }

    /// Wake-on-LAN. Works only if the TV has "Power on with Mobile/Wi-Fi" enabled.
    func powerOn() {
        guard let mac else { state = .failed("Connect to the TV once while it is on to learn its MAC address."); return }
        let hex = mac.filter(\.isHexDigit)
        var bytes = [UInt8]()
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            if let b = UInt8(hex[i..<j], radix: 16) { bytes.append(b) }
            i = j
        }
        guard bytes.count == 6 else { return }
        let packet = [UInt8](repeating: 0xFF, count: 6) + Array(repeating: bytes, count: 16).flatMap { $0 }
        sendBroadcast(packet)
    }

    private func sendBroadcast(_ packet: [UInt8]) {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_BROADCAST
        for port: UInt16 in [9, 7] {
            addr.sin_port = port.bigEndian
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = sendto(fd, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    // MARK: Discovery (SSDP)

    func scan() {
        scanning = true
        discovered = []
        Task.detached {
            var ips = TVClient.ssdpSearch()
            if ips.isEmpty { ips = await TVClient.subnetSweep() }  // multicast is often blocked; probe the /24 directly
            var found: [(ip: String, name: String)] = []
            for ip in ips {
                guard let url = URL(string: "http://\(ip):8001/api/v2/"),
                      let (data, _) = try? await URLSession.shared.data(from: url),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let device = obj["device"] as? [String: Any] else { continue }
                found.append((ip, (device["name"] as? String) ?? (device["modelName"] as? String) ?? ip))
            }
            await self.finishScan(found)
        }
    }

    /// Connect straight away: keep the current IP if it was found again, otherwise take the first TV.
    private func finishScan(_ found: [(ip: String, name: String)]) async {
        discovered = found
        scanning = false
        guard let pick = found.first(where: { $0.ip == ip }) ?? found.first else {
            state = .failed("No Samsung TV found on this network. Make sure it is on, or enter its IP.")
            return
        }
        ip = pick.ip
        await connect()
    }

    nonisolated private static func localIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { freeifaddrs(head) }
        var p = head
        while let i = p?.pointee {
            defer { p = i.ifa_next }
            guard let a = i.ifa_addr, a.pointee.sa_family == sa_family_t(AF_INET),
                  String(cString: i.ifa_name).hasPrefix("en") else { continue }
            var addr = a.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN))
            let ip = String(cString: buf)
            if !ip.hasPrefix("169.254") { return ip }
        }
        return nil
    }

    /// Probe every host in this Mac's /24 for Samsung's :8001 API.
    nonisolated private static func subnetSweep() async -> Set<String> {
        guard let local = localIPv4() else { return [] }
        let prefix = local.split(separator: ".").prefix(3).joined(separator: ".")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 1.5
        let session = URLSession(configuration: cfg)
        return await withTaskGroup(of: String?.self) { group in
            for n in 1...254 {
                let ip = "\(prefix).\(n)"
                group.addTask {
                    guard let url = URL(string: "http://\(ip):8001/api/v2/"),
                          let (data, _) = try? await session.data(from: url),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          obj["device"] != nil else { return nil }
                    return ip
                }
            }
            var found = Set<String>()
            for await ip in group { if let ip { found.insert(ip) } }
            return found
        }
    }

    nonisolated private static func ssdpSearch() -> Set<String> {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let msg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: urn:dial-multiscreen-org:service:dial:1\r\n\r\n"
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &addr.sin_addr)
        let bytes = Array(msg.utf8)
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        var ips = Set<String>()
        let deadline = Date().addingTimeInterval(3)
        var buf = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            var from = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buf, buf.count, 0, $0, &len)
                }
            }
            if n < 0 { continue }
            var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &from.sin_addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
            ips.insert(String(cString: ipBuf))
        }
        return ips
    }
}

// Accept the TV's self-signed certificate.
extension TVClient: URLSessionDelegate {
    nonisolated func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                                completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

struct TimeoutError: Error {}
struct TVDenied: Error {}

func withTimeout<T>(seconds: Double, _ op: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await op() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

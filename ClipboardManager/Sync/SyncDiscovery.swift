import Foundation
import Network
import Darwin

/// 使用 Bonjour 广播本机服务并发现局域网内的其他客户端
class SyncDiscovery: ObservableObject {
    static let serviceType = "_clipmgr._tcp"
    static let serviceDomain = "local."

    @Published var discoveredPeers: [DiscoveredPeer] = []

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var broadcastDiscovery: SyncBroadcastDiscovery?
    private var isRunning = false
    private var restartWorkItem: DispatchWorkItem?
    private var bonjourPeers: [String: DiscoveredPeer] = [:]
    private var broadcastPeers: [String: DiscoveredPeer] = [:]
    private var broadcastPeerLastSeen: [String: Date] = [:]
    private var broadcastCleanupTimer: DispatchSourceTimer?
    private var lastPublishedPeerNames = Set<String>()

    /// 本机 Bonjour 服务名（= localID），用于过滤自身
    private let localServiceName: String

    /// 发现新连接入站时回调（接收方）
    var onIncomingConnection: ((NWConnection) -> Void)?

    init(localServiceName: String) {
        self.localServiceName = localServiceName
    }

    // MARK: - 启动

    func start(port: NWEndpoint.Port = .any) {
        guard !isRunning else { return }
        isRunning = true
        log(.info, "start localServiceName=\(localServiceName)")
        startListener(port: port)
        startBrowser()
        startBroadcastDiscovery(port: port)
    }

    func stop() {
        isRunning = false
        restartWorkItem?.cancel()
        restartWorkItem = nil
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        broadcastDiscovery?.stop()
        broadcastDiscovery = nil
        broadcastCleanupTimer?.cancel()
        broadcastCleanupTimer = nil
        bonjourPeers.removeAll()
        broadcastPeers.removeAll()
        broadcastPeerLastSeen.removeAll()
        lastPublishedPeerNames.removeAll()
        DispatchQueue.main.async { self.discoveredPeers = [] }
    }

    // MARK: - 广播（用 localID 作为服务名，保证唯一）

    private func startListener(port: NWEndpoint.Port) {
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        guard let listener = try? NWListener(using: params, on: port) else {
            log(.error, "failed to create NWListener")
            scheduleRestart(reason: "listener create failed")
            return
        }
        listener.service = NWListener.Service(name: localServiceName, type: Self.serviceType)

        listener.newConnectionHandler = { [weak self] connection in
            self?.log(.debug, "incoming connection endpoint=\(connection.endpoint)")
            self?.onIncomingConnection?(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            self?.log(.debug, "listener state=\(state)")
            switch state {
            case .failed(let error):
                self?.log(.error, "listener failed error=\(error)")
                self?.listener?.cancel()
                self?.listener = nil
                self?.scheduleRestart(reason: "listener failed")
            case .cancelled:
                self?.listener = nil
            default:
                break
            }
        }
        listener.start(queue: .global(qos: .utility))
        self.listener = listener
    }

    // MARK: - 发现（过滤掉自身）

    private func startBrowser() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: Self.serviceDomain), using: params)

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            let peers = results.compactMap { result -> DiscoveredPeer? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                // 过滤掉自身广播的服务
                guard name != self.localServiceName else { return nil }
                return DiscoveredPeer(name: name, endpoint: result.endpoint, host: nil, port: nil)
            }
            self.log(.debug, "browse results count=\(results.count) peers=\(peers.map(\.name).joined(separator: ","))")
            self.bonjourPeers = Dictionary(uniqueKeysWithValues: peers.map { ($0.name, $0) })
            self.publishMergedPeers()
        }
        browser.stateUpdateHandler = { [weak self] state in
            self?.log(.debug, "browser state=\(state)")
            switch state {
            case .failed(let error):
                self?.log(.error, "browser failed error=\(error)")
                self?.browser?.cancel()
                self?.browser = nil
                self?.scheduleRestart(reason: "browser failed")
            case .cancelled:
                self?.browser = nil
            default:
                break
            }
        }
        browser.start(queue: .global(qos: .utility))
        self.browser = browser
    }

    // MARK: - 主动连接

    func connect(to peer: DiscoveredPeer) -> NWConnection {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        if let host = peer.host, let port = peer.port {
            log(.info, "connect to peer=\(peer.name) host=\(host) port=\(port) via=broadcast")
            return NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port)),
                using: params
            )
        }
        log(.info, "connect to peer=\(peer.name) endpoint=\(peer.endpoint.debugDescription) via=bonjour")
        if let endpoint = peer.endpoint {
            return NWConnection(to: endpoint, using: params)
        }
        return NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: 9,
            using: params
        )
    }

    private func startBroadcastDiscovery(port: NWEndpoint.Port) {
        let portValue: UInt16
        switch port {
        case .any:
            guard let actualPort = listener?.port?.rawValue else {
                log(.warn, "broadcast start skipped; listener port unavailable")
                return
            }
            portValue = actualPort
        default:
            portValue = port.rawValue
        }

        log(.info, "starting broadcast discovery localID=\(localServiceName) port=\(portValue)")
        let discovery = SyncBroadcastDiscovery(
            localID: localServiceName,
            localName: Host.current().localizedName ?? "Mac",
            serverPort: Int(portValue)
        )
        discovery.onPeerDiscovered = { [weak self] peer in
            guard let self else { return }
            self.log(.debug, "broadcast peer discovered id=\(peer.name) host=\(peer.host ?? "") port=\(peer.port ?? 0)")
            self.broadcastPeers[peer.name] = peer
            self.broadcastPeerLastSeen[peer.name] = Date()
            self.publishMergedPeers()
        }
        discovery.start()
        broadcastDiscovery = discovery
        startBroadcastCleanupTimer()
    }

    func boostActivity() {
        broadcastDiscovery?.boostBurst()
    }

    private func publishMergedPeers() {
        let merged = Array(Set(bonjourPeers.keys).union(broadcastPeers.keys)).compactMap { peerName -> DiscoveredPeer? in
            let bonjourPeer = bonjourPeers[peerName]
            let broadcastPeer = broadcastPeers[peerName]
            guard bonjourPeer != nil || broadcastPeer != nil else { return nil }
            return DiscoveredPeer(
                name: peerName,
                endpoint: bonjourPeer?.endpoint,
                host: broadcastPeer?.host ?? bonjourPeer?.host,
                port: broadcastPeer?.port ?? bonjourPeer?.port
            )
        }
        let mergedNames = Set(merged.map(\.name))
        let newlyDiscovered = mergedNames.subtracting(lastPublishedPeerNames)
        for name in newlyDiscovered.sorted() {
            log(.info, "discovered peer name=\(name)")
        }
        lastPublishedPeerNames = mergedNames
        DispatchQueue.main.async {
            self.discoveredPeers = merged.sorted { $0.name < $1.name }
        }
    }

    private func startBroadcastCleanupTimer() {
        broadcastCleanupTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 5.0, repeating: 5.0)
        timer.setEventHandler { [weak self] in
            self?.pruneExpiredBroadcastPeers()
        }
        timer.resume()
        broadcastCleanupTimer = timer
    }

    private func pruneExpiredBroadcastPeers() {
        let cutoff = Date().addingTimeInterval(-45)
        let expiredNames = broadcastPeerLastSeen.compactMap { name, lastSeen in
            lastSeen < cutoff ? name : nil
        }
        guard !expiredNames.isEmpty else { return }
        for name in expiredNames {
            broadcastPeerLastSeen.removeValue(forKey: name)
            broadcastPeers.removeValue(forKey: name)
            log(.info, "expired stale broadcast peer name=\(name)")
        }
        publishMergedPeers()
    }

    private func scheduleRestart(reason: String) {
        guard isRunning else { return }
        restartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            self.log(.info, "restarting discovery reason=\(reason)")
            self.listener?.cancel()
            self.listener = nil
            self.browser?.cancel()
            self.browser = nil
            self.startListener(port: .any)
            self.startBrowser()
        }
        restartWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func log(_ level: AppLogLevel = .debug, _ message: String) {
        AppLogger.shared.log(level, "SyncDiscovery", message)
    }
}

// MARK: - DiscoveredPeer

struct DiscoveredPeer: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let endpoint: NWEndpoint?
    let host: String?
    let port: Int?

    static func == (lhs: DiscoveredPeer, rhs: DiscoveredPeer) -> Bool {
        lhs.name == rhs.name
    }
}

private final class SyncBroadcastDiscovery {
    private static let broadcastPort: UInt16 = 44561
    private static let signature = "clipmgr-sync-v1"

    var onPeerDiscovered: ((DiscoveredPeer) -> Void)?

    private let localID: String
    private let localName: String
    private let serverPort: Int
    private let advertisedHost: String?
    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var announceTimer: DispatchSourceTimer?
    private let burstDuration: TimeInterval = 10
    private let burstInterval: TimeInterval = 2
    private let steadyInterval: TimeInterval = 15
    private var cadenceStart: Date?
    private var didLogSteadyCadence = false

    init(localID: String, localName: String, serverPort: Int) {
        self.localID = localID
        self.localName = localName
        self.serverPort = serverPort
        self.advertisedHost = Self.selectPreferredLocalIPv4()
    }

    func start() {
        stop()

        socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else {
            log(.error, "socket create failed")
            return
        }

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socketFD, SOL_SOCKET, SO_BROADCAST, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(Self.broadcastPort)
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            log(.error, "bind failed on port \(Self.broadcastPort)")
            stop()
            return
        }
        log(.info, "listening on UDP broadcast port \(Self.broadcastPort)")
        if let advertisedHost {
            log(.info, "selectedIPv4=\(advertisedHost)")
        } else {
            log(.warn, "selectedIPv4 unavailable; receiver will use packet source IP")
        }

        let queue = DispatchQueue.global(qos: .utility)
        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.receivePacket()
        }
        source.setCancelHandler { [fd = socketFD] in
            if fd >= 0 {
                close(fd)
            }
        }
        source.resume()
        readSource = source

        cadenceStart = Date()
        didLogSteadyCadence = false
        log(.info, "broadcast cadence started burstInterval=\(Int(burstInterval))s steadyInterval=\(Int(steadyInterval))s")
        sendAnnouncement()
        scheduleNextAnnouncement(after: nextAnnouncementInterval(), on: queue)
    }

    func stop() {
        announceTimer?.cancel()
        announceTimer = nil
        readSource?.cancel()
        readSource = nil
        if socketFD >= 0 {
            shutdown(socketFD, SHUT_RDWR)
        }
        socketFD = -1
    }

    func boostBurst() {
        guard socketFD >= 0 else { return }
        cadenceStart = Date()
        didLogSteadyCadence = false
        log(.info, "broadcast cadence boosted to burst mode")
        sendAnnouncement()
        scheduleNextAnnouncement(after: nextAnnouncementInterval(), on: .global(qos: .utility))
    }

    private func sendAnnouncement() {
        guard socketFD >= 0 else { return }
        var payload: [String: Any] = [
            "signature": Self.signature,
            "id": localID,
            "name": localName,
            "port": serverPort
        ]
        if let advertisedHost {
            payload["host"] = advertisedHost
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = CFSwapInt16HostToBig(Self.broadcastPort)
        dest.sin_addr = in_addr(s_addr: inet_addr("255.255.255.255"))

        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            withUnsafePointer(to: &dest) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = sendto(socketFD, baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        log(.debug, "broadcast announce id=\(localID) name=\(localName) port=\(serverPort) host=\(advertisedHost ?? "packet-source")")
    }

    private func receivePacket() {
        guard socketFD >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 2048)
        var sender = sockaddr_in()
        var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let received = withUnsafeMutablePointer(to: &sender) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(socketFD, &buffer, buffer.count, 0, $0, &senderLen)
            }
        }

        guard received > 0 else { return }
        let data = Data(buffer.prefix(received))
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let signature = object["signature"] as? String,
              signature == Self.signature,
              let id = object["id"] as? String,
              let port = object["port"] as? Int,
              id != localID else { return }

        let senderIP = String(cString: inet_ntoa(sender.sin_addr))
        let host = (object["host"] as? String).flatMap { Self.isPrivateIPv4($0) ? $0 : nil } ?? senderIP
        log(.debug, "broadcast packet received id=\(id) host=\(host) sender=\(senderIP) port=\(port)")
        let peer = DiscoveredPeer(name: id, endpoint: nil, host: host, port: port)
        onPeerDiscovered?(peer)
    }

    private func nextAnnouncementInterval() -> TimeInterval {
        guard let cadenceStart else { return steadyInterval }
        let elapsed = Date().timeIntervalSince(cadenceStart)
        if elapsed < burstDuration {
            return burstInterval
        }
        if !didLogSteadyCadence {
            didLogSteadyCadence = true
            log(.info, "broadcast cadence switched to steady interval=\(Int(steadyInterval))s")
        }
        return steadyInterval
    }

    private func scheduleNextAnnouncement(after interval: TimeInterval, on queue: DispatchQueue) {
        announceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.sendAnnouncement()
            self.scheduleNextAnnouncement(after: self.nextAnnouncementInterval(), on: queue)
        }
        timer.resume()
        announceTimer = timer
    }

    private static func selectPreferredLocalIPv4() -> String? {
        let candidates = localIPv4Candidates()
        if let preferred = candidates.first(where: { candidate in
            let lowercased = candidate.interface.lowercased()
            return lowercased.contains("en0") || lowercased.contains("en1") || lowercased.contains("bridge")
        }) {
            return preferred.address
        }
        return candidates.first?.address
    }

    private static func localIPv4Candidates() -> [(interface: String, address: String)] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }

        var results: [(String, String)] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current?.pointee {
            defer { current = entry.ifa_next }
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }

            let interfaceName = String(cString: entry.ifa_name)
            let flags = Int32(entry.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            let addressString = String(cString: hostBuffer)
            guard isPrivateIPv4(addressString) else { continue }
            results.append((interfaceName, addressString))
        }
        return results
    }

    private static func isPrivateIPv4(_ address: String) -> Bool {
        let octets = address.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        if octets[0] == 10 { return true }
        if octets[0] == 172, (16...31).contains(octets[1]) { return true }
        if octets[0] == 192, octets[1] == 168 { return true }
        return false
    }

    private func log(_ level: AppLogLevel = .debug, _ message: String) {
        AppLogger.shared.log(level, "SyncBroadcast", message)
    }
}

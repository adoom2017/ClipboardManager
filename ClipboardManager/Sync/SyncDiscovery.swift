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
        log("start localServiceName=\(localServiceName)")
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
        bonjourPeers.removeAll()
        broadcastPeers.removeAll()
        DispatchQueue.main.async { self.discoveredPeers = [] }
    }

    // MARK: - 广播（用 localID 作为服务名，保证唯一）

    private func startListener(port: NWEndpoint.Port) {
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        guard let listener = try? NWListener(using: params, on: port) else {
            log("failed to create NWListener")
            scheduleRestart(reason: "listener create failed")
            return
        }
        listener.service = NWListener.Service(name: localServiceName, type: Self.serviceType)

        listener.newConnectionHandler = { [weak self] connection in
            self?.log("incoming connection endpoint=\(connection.endpoint)")
            self?.onIncomingConnection?(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            self?.log("listener state=\(state)")
            switch state {
            case .failed(let error):
                self?.log("listener failed error=\(error)")
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
            self.log("browse results count=\(results.count) peers=\(peers.map(\.name).joined(separator: ","))")
            self.bonjourPeers = Dictionary(uniqueKeysWithValues: peers.map { ($0.name, $0) })
            self.publishMergedPeers()
        }
        browser.stateUpdateHandler = { [weak self] state in
            self?.log("browser state=\(state)")
            switch state {
            case .failed(let error):
                self?.log("browser failed error=\(error)")
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
        log("connect to peer=\(peer.name) endpoint=\(peer.endpoint)")
        if let endpoint = peer.endpoint {
            return NWConnection(to: endpoint, using: params)
        }
        if let host = peer.host, let port = peer.port {
            return NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port)),
                using: params
            )
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
                log("broadcast start skipped; listener port unavailable")
                return
            }
            portValue = actualPort
        default:
            portValue = port.rawValue
        }

        let discovery = SyncBroadcastDiscovery(
            localID: localServiceName,
            localName: Host.current().localizedName ?? "Mac",
            serverPort: Int(portValue)
        )
        discovery.onPeerDiscovered = { [weak self] peer in
            guard let self else { return }
            self.log("broadcast peer discovered id=\(peer.name) host=\(peer.host ?? "") port=\(peer.port ?? 0)")
            self.broadcastPeers[peer.name] = peer
            self.publishMergedPeers()
        }
        discovery.start()
        broadcastDiscovery = discovery
    }

    private func publishMergedPeers() {
        let merged = Array(bonjourPeers.values) + broadcastPeers.values.filter { bonjourPeers[$0.name] == nil }
        DispatchQueue.main.async {
            self.discoveredPeers = merged.sorted { $0.name < $1.name }
        }
    }

    private func scheduleRestart(reason: String) {
        guard isRunning else { return }
        restartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            self.log("restarting discovery reason=\(reason)")
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

    private func log(_ message: String) {
        print("[SyncDiscovery] \(message)")
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
    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var announceTimer: DispatchSourceTimer?

    init(localID: String, localName: String, serverPort: Int) {
        self.localID = localID
        self.localName = localName
        self.serverPort = serverPort
    }

    func start() {
        stop()

        socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else { return }

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
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
            stop()
            return
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

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.sendAnnouncement()
        }
        timer.resume()
        announceTimer = timer
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

    private func sendAnnouncement() {
        guard socketFD >= 0 else { return }
        let payload: [String: Any] = [
            "signature": Self.signature,
            "id": localID,
            "name": localName,
            "port": serverPort
        ]
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
        let peer = DiscoveredPeer(name: id, endpoint: nil, host: senderIP, port: port)
        onPeerDiscovered?(peer)
    }
}

import Foundation
import Network

/// 使用 Bonjour 广播本机服务并发现局域网内的其他客户端
class SyncDiscovery: ObservableObject {
    static let serviceType = "_clipmgr._tcp"
    static let serviceDomain = "local."

    @Published var discoveredPeers: [DiscoveredPeer] = []

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var isRunning = false

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
        startListener(port: port)
        startBrowser()
    }

    func stop() {
        isRunning = false
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        DispatchQueue.main.async { self.discoveredPeers = [] }
    }

    // MARK: - 广播（用 localID 作为服务名，保证唯一）

    private func startListener(port: NWEndpoint.Port) {
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        guard let listener = try? NWListener(using: params, on: port) else { return }
        listener.service = NWListener.Service(name: localServiceName, type: Self.serviceType)

        listener.newConnectionHandler = { [weak self] connection in
            self?.onIncomingConnection?(connection)
        }
        listener.stateUpdateHandler = { state in
            print("[SyncDiscovery] Listener state: \(state)")
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
                return DiscoveredPeer(name: name, endpoint: result.endpoint)
            }
            DispatchQueue.main.async { self.discoveredPeers = peers }
        }
        browser.stateUpdateHandler = { state in
            print("[SyncDiscovery] Browser state: \(state)")
        }
        browser.start(queue: .global(qos: .utility))
        self.browser = browser
    }

    // MARK: - 主动连接

    func connect(to peer: DiscoveredPeer) -> NWConnection {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        return NWConnection(to: peer.endpoint, using: params)
    }
}

// MARK: - DiscoveredPeer

struct DiscoveredPeer: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let endpoint: NWEndpoint

    static func == (lhs: DiscoveredPeer, rhs: DiscoveredPeer) -> Bool {
        lhs.name == rhs.name
    }
}

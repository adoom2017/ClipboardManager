import SwiftUI
import Combine

class SyncViewModel: ObservableObject {
    @Published var pairedPeers: [SyncPeer] = []
    @Published var activePeers: [ActivePeer] = []
    @Published var discoveredPeers: [DiscoveredPeer] = []
    @Published var isAutoSyncEnabled: Bool = true

    // 配对相关
    @Published var incomingPIN: String? = nil
    @Published var showPinInput: Bool = false
    @Published var pinInput: String = ""
    @Published var selectedPeerForPairing: DiscoveredPeer? = nil
    @Published var showDiscoveredPeers: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private let service = SyncService.shared
    // 复用 SyncService 内部同一个 SyncDiscovery 实例，避免多个 Bonjour listener/browser
    private var discovery: SyncDiscovery { service.discovery }

    init() {

        service.$pairedPeers
            .receive(on: DispatchQueue.main)
            .assign(to: &$pairedPeers)

        service.$activePeers
            .receive(on: DispatchQueue.main)
            .assign(to: &$activePeers)

        service.$isAutoSyncEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAutoSyncEnabled)

        service.$incomingPairingPIN
            .receive(on: DispatchQueue.main)
            .assign(to: &$incomingPIN)

        discovery.$discoveredPeers
            .receive(on: DispatchQueue.main)
            .assign(to: &$discoveredPeers)

        $isAutoSyncEnabled
            .dropFirst()
            .sink { [weak self] in self?.service.isAutoSyncEnabled = $0 }
            .store(in: &cancellables)
    }

    func startDiscovery() {
        showDiscoveredPeers = true
    }

    func stopDiscovery() {
        showDiscoveredPeers = false
    }

    func connectToPeer(_ peer: DiscoveredPeer) {
        service.connect(to: peer)
        selectedPeerForPairing = peer
        showPinInput = true
    }

    func confirmPin() {
        guard let peer = selectedPeerForPairing,
              let conn = service.pendingPairingConnection else {
            // 发起方：找到对应的 active connection 发送 PIN
            // SyncService 内部管理连接，这里通过 service 接口
            showPinInput = false
            return
        }
        service.confirmPairing(connection: conn, peerID: peer.name, peerName: peer.name, pin: pinInput)
        pinInput = ""
        showPinInput = false
    }

    func removePeer(id: String) {
        service.removePairedPeer(id: id)
    }

    func isOnline(_ peerID: String) -> Bool {
        activePeers.contains { $0.id == peerID }
    }
}

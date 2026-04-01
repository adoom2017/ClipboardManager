import Foundation
import Network
import Combine

class SyncService: ObservableObject {
    static let shared = SyncService()

    @Published var discoveredPeers: [DiscoveredPeer] = []

    private let localID: String
    private let localName: String
    lazy var discovery: SyncDiscovery = SyncDiscovery(localServiceName: self.localID)
    private var cancellables = Set<AnyCancellable>()

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "syncLocalDeviceID") {
            localID = saved
        } else {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: "syncLocalDeviceID")
            localID = newID
        }
        localName = Host.current().localizedName ?? "Mac"
        setupDiscovery()
        discovery.$discoveredPeers
            .receive(on: DispatchQueue.main)
            .assign(to: &$discoveredPeers)
    }

    func start() {
        log(.info, "start localID=\(localID) localName=\(localName)")
        discovery.start()
    }

    func stop() {
        log(.info, "stop")
        discovery.stop()
    }

    func syncItem(_ item: ClipboardItem, to peer: DiscoveredPeer) {
        guard item.contentType == .text else { return }
        log(.info, "syncItem itemID=\(item.id.uuidString) peer=\(peer.name)")

        let nwConnection = discovery.connect(to: peer)
        let connection = SyncConnection(connection: nwConnection, peerID: peer.name, peerName: peer.name)
        connection.onReady = { [weak self, weak connection] readyConnection in
            guard let self, let connection else { return }
            let hello = SyncMessage(type: .hello, senderID: self.localID, senderName: self.localName)
            connection.send(message: hello)
            self.sendItems([item], via: readyConnection)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
                connection.cancel()
            }
        }
        connection.onDisconnect = { [weak self] disconnected in
            self?.log(.debug, "connection disconnected peerID=\(disconnected.peerID) peerName=\(disconnected.peerName)")
        }
        connection.onMessage = { [weak self] message in
            self?.handle(message: message, from: connection)
        }
        connection.start()
    }

    private func setupDiscovery() {
        discovery.onIncomingConnection = { [weak self] nwConnection in
            guard let self else { return }
            let connection = SyncConnection(connection: nwConnection)
            connection.onMessage = { [weak self] message in
                self?.handle(message: message, from: connection)
            }
            connection.onDisconnect = { [weak self] disconnected in
                self?.log(.debug, "incoming disconnected peerID=\(disconnected.peerID) peerName=\(disconnected.peerName)")
            }
            connection.start()
        }
    }

    private func handle(message: SyncMessage, from connection: SyncConnection) {
        log(.debug, "handle type=\(message.type.rawValue) senderID=\(message.senderID) senderName=\(message.senderName)")
        switch message.type {
        case .hello:
            break
        case .items:
            guard let payloadData = message.plainPayload,
                  let payload = try? JSONDecoder().decode(SyncItemsPayload.self, from: payloadData) else {
                log(.warn, "failed to decode items payload from senderID=\(message.senderID)")
                connection.cancel()
                return
            }
            log(.info, "decoded \(payload.items.count) synced item(s) from senderID=\(message.senderID)")
            receiveItems(payload.items)
            connection.cancel()
        case .ack:
            connection.cancel()
        case .ping:
            let pong = SyncMessage(type: .pong, senderID: localID, senderName: localName)
            connection.send(message: pong)
        case .pong:
            break
        }
    }

    func boostDiscovery() {
        discovery.boostActivity()
    }

    private func sendItems(_ items: [ClipboardItem], via connection: SyncConnection) {
        let syncItems = items.filter { $0.contentType == .text }.map {
            SyncClipboardItem(
                id: $0.id.uuidString,
                content: $0.content,
                timestamp: $0.timestamp,
                sourceApp: $0.sourceApp,
                isPinned: $0.isPinned
            )
        }
        guard !syncItems.isEmpty,
              let payload = try? JSONEncoder().encode(SyncItemsPayload(items: syncItems)) else { return }

        var message = SyncMessage(type: .items, senderID: localID, senderName: localName)
        message.plainPayload = payload
        connection.send(message: message)
    }

    private func receiveItems(_ items: [SyncClipboardItem]) {
        DispatchQueue.main.async {
            let store = ClipboardStore.shared
            for syncItem in items {
                guard let uuid = UUID(uuidString: syncItem.id) else {
                    self.log(.warn, "skip synced item because id is not UUID id=\(syncItem.id)")
                    continue
                }
                if store.fetchAllItems().contains(where: { $0.id == uuid }) {
                    self.log(.debug, "skip synced item because id already exists id=\(syncItem.id)")
                    continue
                }
                let item = ClipboardItem(
                    id: uuid,
                    contentType: .text,
                    content: syncItem.content,
                    timestamp: syncItem.timestamp,
                    sourceApp: "📡 \(syncItem.sourceApp)",
                    isPinned: false
                )
                self.log(.debug, "store synced item id=\(syncItem.id) sourceApp=\(syncItem.sourceApp)")
                store.addItem(item)
            }
        }
    }

    private func log(_ level: AppLogLevel = .debug, _ message: String) {
        AppLogger.shared.log(level, "SyncService", message)
    }
}

import Foundation
import Network
import Combine

class SyncService: ObservableObject {
    static let shared = SyncService()

    @Published var discoveredPeers: [DiscoveredPeer] = []
    @Published var syncErrorMessage: String?

    private let localID: String
    private let localName: String
    lazy var discovery: SyncDiscovery = SyncDiscovery(localServiceName: self.localID)
    private var cancellables = Set<AnyCancellable>()
    /// 进行中的连接（仅主线程访问）。断开时移除，回调闭包只弱引用连接，避免循环引用泄漏。
    private var activeConnections: [UUID: SyncConnection] = [:]

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

    func clearSyncError() {
        syncErrorMessage = nil
    }

    func syncItem(_ item: ClipboardItem, to peer: DiscoveredPeer) {
        guard item.contentType == .text else { return }
        clearSyncError()
        guard let pin = SecureCredentialStore.shared.value(for: "syncPIN"), pin.count == 6 else {
            syncErrorMessage = "请先在同步设置中配置 6 位同步 PIN。"
            return
        }
        log(.info, "syncItem itemID=\(item.id.uuidString) peer=\(peer.displayName) peerID=\(peer.peerID)")

        let nwConnection = discovery.connect(to: peer)
        let connection = SyncConnection(connection: nwConnection, peerID: peer.peerID, peerName: peer.displayName)
        activeConnections[connection.id] = connection
        var didComplete = false
        let timeout = DispatchWorkItem { [weak self, weak connection] in
            guard let self, !didComplete else { return }
            didComplete = true
            self.log(.warn, "sync timeout itemID=\(item.id.uuidString) peer=\(peer.displayName) peerID=\(peer.peerID)")
            self.syncErrorMessage = "同步到 \(peer.displayName) 超时，请确认设备在线后重试。"
            connection?.cancel()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: timeout)
        connection.onReady = { [weak self, weak connection] readyConnection in
            guard let self, let connection else { return }
            let hello = SyncMessage(type: .hello, senderID: self.localID, senderName: self.localName)
            connection.send(message: hello)
            if let failure = self.sendItems([item], to: peer.peerID, pin: pin, via: readyConnection) {
                guard !didComplete else { return }
                didComplete = true
                timeout.cancel()
                self.syncErrorMessage = failure
                connection.cancel()
            }
        }
        connection.onDisconnect = { [weak self] disconnected in
            guard let self else { return }
            self.activeConnections.removeValue(forKey: disconnected.id)
            if didComplete {
                self.log(.debug, "connection disconnected peerID=\(disconnected.peerID) peerName=\(disconnected.peerName)")
                return
            }
            didComplete = true
            timeout.cancel()
            self.log(.warn, "sync disconnected before ack peerID=\(disconnected.peerID) peerName=\(disconnected.peerName)")
            self.syncErrorMessage = "同步到 \(peer.displayName) 失败，请稍后重试。"
        }
        connection.onFailure = { [weak self] failedConnection, error in
            guard let self, !didComplete else { return }
            didComplete = true
            timeout.cancel()
            self.log(.warn, "sync failed peerID=\(failedConnection.peerID) peerName=\(failedConnection.peerName) error=\(String(describing: error))")
            self.syncErrorMessage = "无法连接到 \(peer.displayName)，请确认设备在线后重试。"
        }
        connection.onMessage = { [weak self, weak connection] message in
            guard let connection else { return }
            if message.type == .ack {
                guard !didComplete else { return }
                didComplete = true
                timeout.cancel()
                self?.log(.info, "sync acknowledged itemID=\(item.id.uuidString) peer=\(peer.displayName) peerID=\(peer.peerID)")
                connection.cancel()
                return
            }
            self?.handle(message: message, from: connection)
        }
        connection.start()
    }

    private func setupDiscovery() {
        discovery.onIncomingConnection = { [weak self] nwConnection in
            DispatchQueue.main.async {
                guard let self else {
                    nwConnection.cancel()
                    return
                }
                let connection = SyncConnection(connection: nwConnection)
                self.activeConnections[connection.id] = connection
                connection.onMessage = { [weak self, weak connection] message in
                    guard let connection else { return }
                    self?.handle(message: message, from: connection)
                }
                connection.onDisconnect = { [weak self] disconnected in
                    self?.activeConnections.removeValue(forKey: disconnected.id)
                    self?.log(.debug, "incoming disconnected peerID=\(disconnected.peerID) peerName=\(disconnected.peerName)")
                }
                connection.start()
            }
        }
    }

    private func handle(message: SyncMessage, from connection: SyncConnection) {
        log(.debug, "handle type=\(message.type.rawValue) senderID=\(message.senderID) senderName=\(message.senderName)")
        switch message.type {
        case .hello:
            break
        case .items:
            guard let encryptedPayload = message.encryptedPayload,
                  let pin = SecureCredentialStore.shared.value(for: "syncPIN"), pin.count == 6 else {
                log(.warn, "reject unencrypted items payload from senderID=\(message.senderID)")
                connection.cancel()
                return
            }
            let key = SyncCrypto.deriveKey(pin: pin, localID: localID, remoteID: message.senderID)
            guard let payloadData = try? SyncCrypto.decrypt(encryptedPayload, using: key),
                  let payload = try? JSONDecoder().decode(SyncItemsPayload.self, from: payloadData) else {
                log(.warn, "failed to decrypt items payload from senderID=\(message.senderID)")
                connection.cancel()
                return
            }
            log(.info, "decoded \(payload.items.count) synced item(s) from senderID=\(message.senderID)")
            receiveItems(payload.items)
            let ack = SyncMessage(type: .ack, senderID: localID, senderName: localName)
            connection.send(message: ack)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                connection.cancel()
            }
        case .ack:
            break
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

    /// 发送成功返回 nil；失败返回可展示给用户的错误信息，由调用方结束本次同步。
    private func sendItems(_ items: [ClipboardItem], to remoteID: String, pin: String, via connection: SyncConnection) -> String? {
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
              let payload = try? JSONEncoder().encode(SyncItemsPayload(items: syncItems)) else {
            return "无法编码同步内容。"
        }

        let key = SyncCrypto.deriveKey(pin: pin, localID: localID, remoteID: remoteID)
        guard let encryptedPayload = try? SyncCrypto.encrypt(payload, using: key) else {
            return "无法加密同步内容。"
        }
        var message = SyncMessage(type: .items, senderID: localID, senderName: localName)
        message.encryptedPayload = encryptedPayload
        guard (try? message.toFrameData()) != nil else {
            log(.warn, "sync payload too large bytes=\(encryptedPayload.count) remoteID=\(remoteID)")
            return "内容过大，无法同步（单条上限约 7MB 文本）。"
        }
        connection.send(message: message)
        return nil
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

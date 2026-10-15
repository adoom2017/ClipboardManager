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
            if message.type == .error {
                guard !didComplete else { return }
                didComplete = true
                timeout.cancel()
                self?.log(.warn, "sync rejected errorCode=\(message.errorCode ?? "") peer=\(peer.displayName) peerID=\(peer.peerID)")
                self?.syncErrorMessage = message.errorCode.flatMap(SyncErrorCode.init(rawValue:))?
                    .userMessage(peerName: peer.displayName)
                    ?? "\(peer.displayName) 拒绝了同步内容。"
                connection.cancel()
                return
            }
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
            guard let encryptedPayload = message.encryptedPayload else {
                log(.warn, "reject unencrypted items payload from senderID=\(message.senderID)")
                reject(.invalidPayload, on: connection)
                return
            }
            guard let pin = SecureCredentialStore.shared.value(for: "syncPIN"), pin.count == 6 else {
                log(.warn, "reject items because sync PIN is not configured senderID=\(message.senderID)")
                reject(.pinNotConfigured, on: connection)
                return
            }
            let key = SyncCrypto.deriveKey(pin: pin, localID: localID, remoteID: message.senderID)
            guard let payloadData = try? SyncCrypto.decrypt(encryptedPayload, using: key) else {
                log(.warn, "failed to decrypt items payload from senderID=\(message.senderID)")
                reject(.decryptFailed, on: connection)
                return
            }
            guard let payload = try? JSONDecoder().decode(SyncItemsPayload.self, from: payloadData),
                  let received = Self.receivedItems(
                      from: payload.items,
                      existingIDs: Set(ClipboardStore.shared.fetchAllItems().map(\.id))
                  ) else {
                log(.warn, "invalid items payload from senderID=\(message.senderID)")
                reject(.invalidPayload, on: connection)
                return
            }
            log(.info, "decoded \(payload.items.count) synced item(s), storing \(received.count) from senderID=\(message.senderID)")
            // 末尾的条目先插入，使 payload 中的第一条最终位于列表顶部。
            for item in received.reversed() {
                ClipboardStore.shared.addItem(item)
            }
            // 写入完成后再确认，ACK 表示条目已落库（或因重复已存在）。
            reply(SyncMessage(type: .ack, senderID: localID, senderName: localName), andCloseOn: connection)
        case .ack:
            break
        case .ping:
            let pong = SyncMessage(type: .pong, senderID: localID, senderName: localName)
            connection.send(message: pong)
        case .pong, .error:
            break
        }
    }

    private func reject(_ code: SyncErrorCode, on connection: SyncConnection) {
        var message = SyncMessage(type: .error, senderID: localID, senderName: localName)
        message.errorCode = code.rawValue
        reply(message, andCloseOn: connection)
    }

    private func reply(_ message: SyncMessage, andCloseOn connection: SyncConnection) {
        connection.send(message: message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            connection.cancel()
        }
    }

    static let syncedSourcePrefix = "📡 "

    /// 把对端条目转换为本地条目：按 UUID 去重、忽略对端置顶状态、
    /// 时间戳使用接收时间。任一条目 ID 不是 UUID 时整批拒绝（返回 nil）。
    static func receivedItems(
        from syncItems: [SyncClipboardItem],
        existingIDs: Set<UUID>,
        now: Date = Date()
    ) -> [ClipboardItem]? {
        var seen = existingIDs
        var result: [ClipboardItem] = []
        for (index, syncItem) in syncItems.enumerated() {
            guard let uuid = UUID(uuidString: syncItem.id) else { return nil }
            guard seen.insert(uuid).inserted else { continue }
            let sourceApp = syncItem.sourceApp.hasPrefix(syncedSourcePrefix)
                ? syncItem.sourceApp
                : syncedSourcePrefix + syncItem.sourceApp
            result.append(ClipboardItem(
                id: uuid,
                contentType: .text,
                content: syncItem.content,
                // 逐条递减 1ms，保证批内顺序在按时间排序的一端也稳定。
                timestamp: now.addingTimeInterval(-Double(index) / 1000),
                sourceApp: sourceApp,
                isPinned: false
            ))
        }
        return result
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

    private func log(_ level: AppLogLevel = .debug, _ message: String) {
        AppLogger.shared.log(level, "SyncService", message)
    }
}

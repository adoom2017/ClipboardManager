import Foundation
import Network
import Combine
import CryptoKit

// MARK: - 已配对节点信息（持久化到 UserDefaults）

struct SyncPeer: Codable, Identifiable, Equatable {
    var id: String         // 对端设备 UUID
    var name: String       // 对端设备名称
    var keyData: Data      // 共享密钥 raw bytes
    var lastSeen: Date?

    var symmetricKey: SymmetricKey { SymmetricKey(data: keyData) }

    static func == (lhs: SyncPeer, rhs: SyncPeer) -> Bool { lhs.id == rhs.id }
}

// MARK: - 在线连接状态

struct ActivePeer: Identifiable {
    let id: String
    let name: String
    var connection: SyncConnection
}

// MARK: - SyncService

class SyncService: ObservableObject {
    static let shared = SyncService()

    // MARK: Published 状态

    @Published var pairedPeers: [SyncPeer] = []
    @Published var activePeers: [ActivePeer] = []
    @Published var isAutoSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(isAutoSyncEnabled, forKey: "syncAutoEnabled") }
    }

    /// 等待对端输入时展示给本机用户看的 PIN
    @Published var incomingPairingPIN: String? = nil
    /// 是否有配对请求正在等待确认
    @Published var pendingPairingConnection: SyncConnection? = nil

    // MARK: Private

    private let localID: String
    private let localName: String
    lazy var discovery: SyncDiscovery = SyncDiscovery(localServiceName: self.localID)
    private var cancellables = Set<AnyCancellable>()
    /// peerID -> 等待 PIN 验证的临时密钥
    private var pendingPINs: [String: String] = [:]

    private init() {
        // 持久化本机 ID
        if let saved = UserDefaults.standard.string(forKey: "syncLocalDeviceID") {
            localID = saved
        } else {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: "syncLocalDeviceID")
            localID = newID
        }
        localName = Host.current().localizedName ?? "Mac"
        isAutoSyncEnabled = UserDefaults.standard.object(forKey: "syncAutoEnabled") as? Bool ?? true
        loadPairedPeers()
        setupDiscovery()
        subscribeToClipboard()
    }

    // MARK: - 启动

    func start() {
        log("start localID=\(localID) localName=\(localName)")
        discovery.start()
    }

    func stop() {
        log("stop")
        discovery.stop()
        activePeers.forEach { $0.connection.cancel() }
        activePeers.removeAll()
    }

    // MARK: - 配对 - 接收方（收到配对请求，显示 PIN）

    private func handlePairingRequest(from connection: SyncConnection, message: SyncMessage) {
        let pin = SyncCrypto.generatePIN()
        pendingPINs[message.senderID] = pin
        DispatchQueue.main.async {
            self.incomingPairingPIN = pin
            self.pendingPairingConnection = connection
        }
    }

    // MARK: - 配对 - 发起方（输入 PIN 后调用）

    func confirmPairing(connection: SyncConnection, peerID: String, peerName: String, pin: String) {
        log("confirmPairing peerID=\(peerID) peerName=\(peerName) pin=\(pin)")
        let pinData = Data(pin.utf8)
        var msg = SyncMessage(type: .pairingPin, senderID: localID, senderName: localName)
        msg.plainPayload = pinData
        connection.send(message: msg)
    }

    // MARK: - 连接新的对端（发起方）

    func connect(to peer: DiscoveredPeer) {
        log("connect requested peer=\(peer.name)")
        let nwConn = discovery.connect(to: peer)
        let conn = SyncConnection(connection: nwConn, peerID: "", peerName: peer.name)
        setupConnectionHandlers(conn)
        DispatchQueue.main.async {
            self.pendingPairingConnection = conn
        }
        conn.start()

        // 发送 hello + 配对请求
        let hello = SyncMessage(type: .hello, senderID: localID, senderName: localName)
        conn.send(message: hello)
        let req = SyncMessage(type: .pairingRequest, senderID: localID, senderName: localName)
        conn.send(message: req)
    }

    // MARK: - 手动同步单条

    func syncItem(_ item: ClipboardItem, to peerID: String) {
        guard let active = activePeers.first(where: { $0.id == peerID }),
              let paired = pairedPeers.first(where: { $0.id == peerID }) else { return }
        sendItems([item], via: active.connection, key: paired.symmetricKey)
    }

    /// 同步给所有在线已配对设备
    func syncItemToAll(_ item: ClipboardItem) {
        for active in activePeers {
            guard let paired = pairedPeers.first(where: { $0.id == active.id }) else { continue }
            sendItems([item], via: active.connection, key: paired.symmetricKey)
        }
    }

    func disconnectPeer(id: String) {
        log("disconnectPeer id=\(id)")
        if let idx = activePeers.firstIndex(where: { $0.id == id }) {
            activePeers[idx].connection.cancel()
            activePeers.remove(at: idx)
        }
    }

    func removePairedPeer(id: String) {
        log("removePairedPeer id=\(id)")
        disconnectPeer(id: id)
        pairedPeers.removeAll { $0.id == id }
        savePairedPeers()
    }

    // MARK: - 内部：自动订阅剪贴板

    private func subscribeToClipboard() {
        ClipboardMonitor.shared.$newClipboardContent
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                guard let self, self.isAutoSyncEnabled else { return }
                guard item.contentType == .text else { return }
                self.syncItemToAll(item)
            }
            .store(in: &cancellables)
    }

    // MARK: - 内部：消息处理

    private func setupConnectionHandlers(_ conn: SyncConnection) {
        conn.onMessage = { [weak self] message in
            self?.handle(message: message, from: conn)
        }
        conn.onDisconnect = { [weak self] c in
            self?.log("connection disconnected peerID=\(c.peerID) peerName=\(c.peerName)")
            self?.activePeers.removeAll { $0.id == c.peerID }
        }
    }

    private func handle(message: SyncMessage, from conn: SyncConnection) {
        log("handle type=\(message.type.rawValue) senderID=\(message.senderID) senderName=\(message.senderName)")
        switch message.type {
        case .hello:
            break

        case .pairingRequest:
            handlePairingRequest(from: conn, message: message)

        case .pairingPin:
            // 接收方收到 PIN 确认
            guard let expectedPIN = pendingPINs[message.senderID],
                  let receivedData = message.plainPayload,
                  String(data: receivedData, encoding: .utf8) == expectedPIN else {
                let reject = SyncMessage(type: .pairingReject, senderID: localID, senderName: localName)
                conn.send(message: reject)
                DispatchQueue.main.async {
                    self.incomingPairingPIN = nil
                    self.pendingPairingConnection = nil
                }
                return
            }
            pendingPINs.removeValue(forKey: message.senderID)
            finalizePairing(peerID: message.senderID, peerName: message.senderName,
                            pin: expectedPIN, connection: conn, sendAck: true)

        case .pairingAck:
            // 发起方收到 ack，配对完成
            guard let pinData = message.plainPayload,
                  let pin = String(data: pinData, encoding: .utf8) else { return }
            finalizePairing(peerID: message.senderID, peerName: message.senderName,
                            pin: pin, connection: conn, sendAck: false)

        case .pairingReject:
            log("pairing rejected by senderID=\(message.senderID)")

        case .items:
            guard let paired = pairedPeers.first(where: { $0.id == message.senderID }),
                  let encrypted = message.encryptedPayload,
                  let plainData = try? SyncCrypto.decrypt(encrypted, using: paired.symmetricKey),
                  let payload = try? JSONDecoder().decode(SyncItemsPayload.self, from: plainData) else { return }
            receiveItems(payload.items)

        case .ack, .ping:
            let pong = SyncMessage(type: .pong, senderID: localID, senderName: localName)
            conn.send(message: pong)
        case .pong:
            break
        }
    }

    private func finalizePairing(peerID: String, peerName: String, pin: String,
                                  connection: SyncConnection, sendAck: Bool) {
        log("finalizePairing peerID=\(peerID) peerName=\(peerName) sendAck=\(sendAck)")
        let key = SyncCrypto.deriveKey(pin: pin, localID: localID, remoteID: peerID)
        let peer = SyncPeer(id: peerID, name: peerName, keyData: key.withUnsafeBytes { Data($0) })
        pairedPeers.removeAll { $0.id == peerID }
        pairedPeers.append(peer)
        savePairedPeers()

        let active = ActivePeer(id: peerID, name: peerName, connection: connection)
        activePeers.removeAll { $0.id == peerID }
        activePeers.append(active)

        if sendAck {
            // 接收方发回 ack，把 PIN 回传让发起方也能派生密钥
            var ack = SyncMessage(type: .pairingAck, senderID: localID, senderName: localName)
            ack.plainPayload = Data(pin.utf8)
            connection.send(message: ack)
        }

        DispatchQueue.main.async {
            self.incomingPairingPIN = nil
            self.pendingPairingConnection = nil
        }
    }

    // MARK: - 内部：发送 items

    private func sendItems(_ items: [ClipboardItem], via connection: SyncConnection, key: SymmetricKey) {
        let syncItems = items.filter { $0.contentType == .text }.map {
            SyncClipboardItem(id: $0.id.uuidString, content: $0.content,
                              timestamp: $0.timestamp, sourceApp: $0.sourceApp, isPinned: $0.isPinned)
        }
        guard !syncItems.isEmpty,
              let plainData = try? JSONEncoder().encode(SyncItemsPayload(items: syncItems)),
              let encrypted = try? SyncCrypto.encrypt(plainData, using: key) else { return }

        var msg = SyncMessage(type: .items, senderID: localID, senderName: localName)
        msg.encryptedPayload = encrypted
        connection.send(message: msg)
    }

    // MARK: - 内部：接收 items

    private func receiveItems(_ items: [SyncClipboardItem]) {
        let store = ClipboardStore.shared
        for syncItem in items {
            guard let uuid = UUID(uuidString: syncItem.id) else { continue }
            // 去重
            if store.fetchAllItems().contains(where: { $0.id == uuid }) { continue }
            let item = ClipboardItem(
                id: uuid,
                contentType: .text,
                content: syncItem.content,
                timestamp: syncItem.timestamp,
                sourceApp: "📡 \(syncItem.sourceApp)",
                isPinned: false
            )
            store.addItem(item)
        }
    }

    // MARK: - Discovery 回调

    private func setupDiscovery() {
        discovery.onIncomingConnection = { [weak self] nwConn in
            guard let self else { return }
            let conn = SyncConnection(connection: nwConn)
            self.setupConnectionHandlers(conn)
            conn.start()
        }
    }

    // MARK: - 持久化

    private func savePairedPeers() {
        if let data = try? JSONEncoder().encode(pairedPeers) {
            UserDefaults.standard.set(data, forKey: "syncPairedPeers")
        }
    }

    private func loadPairedPeers() {
        guard let data = UserDefaults.standard.data(forKey: "syncPairedPeers"),
              let peers = try? JSONDecoder().decode([SyncPeer].self, from: data) else { return }
        pairedPeers = peers
    }

    private func log(_ message: String) {
        print("[SyncService] \(message)")
    }
}

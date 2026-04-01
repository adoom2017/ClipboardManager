import Foundation
import Network
import CryptoKit

/// 封装单个 NWConnection，提供帧级消息收发
class SyncConnection {
    let id: UUID = UUID()
    let peerID: String
    let peerName: String
    private let connection: NWConnection
    var sharedKey: SymmetricKey?

    /// 收到完整消息帧时回调（主线程）
    var onMessage: ((SyncMessage) -> Void)?
    /// 连接断开时回调
    var onDisconnect: ((SyncConnection) -> Void)?

    private var receiveBuffer = Data()

    init(connection: NWConnection, peerID: String = "", peerName: String = "") {
        self.connection = connection
        self.peerID = peerID
        self.peerName = peerName
    }

    // MARK: - 启动

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            print("[SyncConnection] state peerName=\(self.peerName) peerID=\(self.peerID) state=\(state)")
            switch state {
            case .ready:
                self.receiveNextFrame()
            case .failed(let error):
                print("[SyncConnection] failed peerName=\(self.peerName) error=\(error)")
                DispatchQueue.main.async { self.onDisconnect?(self) }
            case .cancelled:
                DispatchQueue.main.async { self.onDisconnect?(self) }
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .utility))
    }

    func cancel() {
        print("[SyncConnection] cancel peerName=\(peerName) peerID=\(peerID)")
        connection.cancel()
    }

    // MARK: - 发送

    func send(message: SyncMessage) {
        print("[SyncConnection] send type=\(message.type.rawValue) senderID=\(message.senderID) peerName=\(peerName)")
        guard let frame = try? message.toFrameData() else { return }
        connection.send(content: frame, completion: .contentProcessed { error in
            if let error = error {
                print("[SyncConnection] 发送失败: \(error)")
            }
        })
    }

    /// 发送并自动加密 payload
    func sendEncrypted(message: SyncMessage) {
        send(message: message)
    }

    // MARK: - 接收（帧读取循环）

    private func receiveNextFrame() {
        // 先读 4 字节长度头
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error = error { print("[SyncConnection] 接收错误: \(error)"); return }
            guard let data, data.count == 4 else {
                if isComplete { DispatchQueue.main.async { self.onDisconnect?(self) } }
                return
            }
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self.receiveBody(length: Int(length))
        }
    }

    private func receiveBody(length: Int) {
        guard length > 0, length < 10_000_000 else { receiveNextFrame(); return }
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error = error { print("[SyncConnection] 接收 body 错误: \(error)"); return }
            if let data, let message = try? SyncMessage.from(body: data) {
                print("[SyncConnection] recv type=\(message.type.rawValue) senderID=\(message.senderID) peerName=\(self.peerName)")
                DispatchQueue.main.async { self.onMessage?(message) }
            }
            if isComplete {
                DispatchQueue.main.async { self.onDisconnect?(self) }
            } else {
                self.receiveNextFrame()
            }
        }
    }
}

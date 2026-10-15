# 局域网同步协议

## 范围与兼容性

协议用于 macOS 与 Windows 应用之间手动同步文本条目。图片和文件不通过当前协议发送。两端必须使用支持 `encryptedPayload` 的版本并配置相同的 6 位 PIN；旧版明文 payload 会被拒绝。

## 发现

- Bonjour/mDNS 服务类型：`_clipmgr._tcp`。
- 服务实例使用持久化设备 UUID，显示名称使用主机名。
- 两端同时支持 UDP 广播兜底：端口 `44561`，签名 `clipmgr-sync-v1`。
- 广播 JSON 中的 `host` 字段仅供旧版本参考；接收端以 UDP 数据包的来源地址作为对端地址，避免使用对端误选的 VPN 或虚拟网卡地址。
- Windows 为每个私有局域网 IPv4 网卡各绑定一个发送 socket 分别广播，因为 `255.255.255.255` 只从绑定的网卡发出。
- macOS 对 45 秒未刷新的 UDP 广播记录执行过期清理，Bonjour 记录由系统浏览结果管理；Windows 对合并后的发现记录执行 45 秒过期清理。
- TCP 服务绑定动态端口，通过发现记录发布。

## 连接与帧

每次同步临时建立 TCP 连接。每个消息帧为：

```text
uint32 bodyLength (big-endian)
JSON body (UTF-8)
```

消息类型：

| 类型 | 用途 |
|---|---|
| `hello` | 发送设备 ID 和名称 |
| `items` | 携带 `encryptedPayload` |
| `ack` | 确认条目已落库（或因重复已存在） |
| `error` | 接收端拒绝 `items`，携带 `errorCode` |
| `ping` / `pong` | 连接探测 |

接收端遇到无法识别的消息类型时直接丢弃，不作为 `ping` 处理。

`error` 消息的 `errorCode` 取值：

| errorCode | 含义 |
|---|---|
| `pinNotConfigured` | 接收端未配置 6 位 PIN |
| `decryptFailed` | 解密失败，通常是两端 PIN 不一致 |
| `invalidPayload` | 缺少 `encryptedPayload`，或解密后的 JSON 结构、条目 ID 不合法 |

发送端收到未知 `errorCode` 时按通用失败提示。旧版本会忽略 `error` 消息，此时发送端仍表现为断开或超时。

发送端 TCP 连接超时 3 秒（Windows 显式设置；macOS 的 3 秒整体超时从发起连接开始计时），等待 ACK 超时 3 秒。

单帧 body 长度必须大于 0 且小于 10,000,000 字节，两端收发都执行此限制：发送端超限时直接报错，不发送；接收端读到非法长度时无法重新对齐帧边界，会立即断开连接。

## 密钥派生

双方按字典序排序设备 ID，然后使用 HKDF-SHA256 派生 32 字节 AES 密钥：

```text
IKM  = UTF8("ClipboardManagerSync")
salt = UTF8("<smallerDeviceID>:<largerDeviceID>:<6-digit PIN>")
info = UTF8("v1-sync-key")
L    = 32 bytes
```

PIN 保存在 macOS Keychain 或 Windows DPAPI 保护的设置中，不进入网络消息。
派生出的 AES 密钥只用于当前同步操作的内存计算，不得序列化到设置、文件、日志或测试夹具；后续同步必须从 PIN 与设备 ID 重新派生。

## 加密 payload

- 算法：AES-GCM-256。
- nonce：每条消息随机生成 12 字节。
- tag：16 字节。
- 二进制布局：`nonce || ciphertext || tag`。
- JSON 字段：`encryptedPayload`，值为上述二进制的 Base64。

解密失败、未配置 PIN 或缺少 `encryptedPayload` 时，接收端回复对应的 `error` 消息后关闭连接，不写入历史。

## 明文结构

加密前的 JSON 包含 `items` 数组。当前发送端只产生文本条目：

```json
{
  "items": [
    {
      "id": "UUID",
      "content": "text",
      "timestamp": 123456789.0,
      "sourceApp": "Application",
      "isPinned": false
    }
  ]
}
```

时间戳采用 Apple reference date（2001-01-01 UTC）起的秒数，以兼容 Swift `JSONEncoder` 默认日期格式。

两端接收语义一致：

- `id` 必须是 UUID（大小写不敏感）；任一条目 `id` 非 UUID 或 `content` 不是字符串时整批拒绝，回复 `invalidPayload`。
- 按 UUID 去重，大小写不敏感：本地已存在或同批重复的条目直接跳过。重放旧消息不会产生重复条目。
- 忽略发送端的 `isPinned`，同步条目一律保存为未置顶。
- 时间戳使用接收时间，避免两端时钟偏差，也避免旧条目同步后被保留期清理立即删除；同批条目逐条递减 1 毫秒以保持顺序，payload 中第一条位于最上方。发送端的 `timestamp` 仍需发送以兼容旧版本。
- 来源应用加 `📡 ` 前缀标记同步条目，已有前缀时不重复添加。
- 去重后的条目仍经过本地 `ClipboardStore` 的内容去重规则。
- 全部条目写入（或因重复跳过）后才回复 `ack`。

调整这些语义时必须同时修改两端实现和协议测试（macOS `SyncMessageTests`，Windows `sync_received_items_test.dart`）。

## 安全说明

- 6 位 PIN 只有 100 万种组合，而设备 ID 会在局域网内公开广播。抓到任意一条 `items` 消息的人都可以离线穷举 PIN，在几秒内解密内容。因此当前加密只能防止顺带看到明文，不能抵御有意监听局域网的攻击者。
- 要真正抵御离线穷举，需要改为配对时交换高强度随机密钥，或使用 PAKE。这是不兼容的协议变更。
- 当前没有证书、设备确认或 PIN 尝试限速；不要在不可信网络同步高敏感内容。
- 不得增加“解密失败后按明文处理”的兼容逻辑。
- 日志不得记录 PIN、派生密钥、明文 payload 或 API Key。
- 测试只使用固定的非生产 PIN、设备 ID 和 nonce；不得从真实凭据导出测试向量。

## 排障

1. 确认两端处于同一私有 IPv4 局域网。
2. 确认防火墙允许 mDNS/UDP 5353、UDP 44561 和发现记录中的动态 TCP 端口。
3. 确认两端 PIN 都是 6 位且完全一致。
4. 看不到设备时，在同步页触发 discovery boost，并检查 mDNS 是否被网络隔离。
5. 能发现但同步失败时，先看发送端的错误提示（来自接收端的 `errorCode`），再检查 3 秒 ACK 超时、设备过期信息以及 `failed to decrypt` 日志。

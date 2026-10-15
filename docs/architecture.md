# 系统架构

## 工作区边界

`ClipboardManager/` 与 `ClipboardManager-Flutter/` 是独立 Git 仓库。代码变更必须提交到对应仓库；跨端共享文档（含同步协议）随 macOS 仓库的 `docs/` 一起版本管理。

```text
clipboard/
├── ClipboardManager/          macOS 原生应用
│   └── docs/                  跨端统一文档
├── ClipboardManager-Flutter/  Windows Flutter 应用
└── AGENTS.md                  工作区 Agent 规则
```

## macOS 应用

### 技术与生命周期

- 最低版本 macOS 14，Swift 5.9，项目由 XcodeGen 的 `project.yml` 生成。
- `ClipboardManagerApp` 提供系统设置场景。
- `AppDelegate` 创建 `NSStatusItem`，并启动日志、剪贴板监听、全局快捷键、自动粘贴跟踪和同步服务。
- `FloatingPanelController` 是菜单栏图标和 `⌥V` 的唯一弹出面板；两个入口共享同一 `NSPanel`、窗口行为和 `ClipboardListViewModel`。

### 模块

| 目录 | 责任 |
|---|---|
| `App/` | SwiftUI 入口和应用生命周期 |
| `Core/` | 剪贴板监听、隐私过滤、自动粘贴、翻译 |
| `Extensions/` | `NSPasteboard` 内容读取辅助方法 |
| `Models/` | `ClipboardItem` 与内容类型 |
| `Storage/` | 内存状态、JSON 和图片文件持久化 |
| `Sync/` | 发现、TCP 连接、消息与加密 |
| `ViewModels/` | 页面状态和 Combine 订阅 |
| `Views/` | 菜单栏、历史、悬停详情、设置、同步和翻译 UI |
| `Utilities/` | Keychain、快捷键、窗口、登录启动和日志 |

### 数据流

```text
NSPasteboard (500ms poll)
  → ClipboardMonitor
  → PrivacyGuard
  → ClipboardStore
  → PersistenceController
  → ClipboardListViewModel
  → SwiftUI Views
```

`ClipboardStore` 是 UI 的唯一历史状态源。测试环境自动使用无 I/O 的内存持久化，避免触碰真实用户数据。

## Windows 应用

### 技术与生命周期

- Flutter/Dart 桌面应用，Windows 能力通过 `win32`、`ffi`、`window_manager`、`tray_manager` 和 `hotkey_manager` 实现。
- `main.dart` 初始化日志、设置、历史、固定尺寸窗口、全局快捷键、监听器和同步服务。
- Windows 启动时窗口隐藏；关闭或失焦时隐藏，托盘“退出”才销毁进程资源。

### 模块

| 目录 | 责任 |
|---|---|
| `lib/core/` | 文本剪贴板轮询、隐私过滤、自动粘贴和翻译 |
| `lib/models/` | 手写 JSON 的 `ClipboardItem` |
| `lib/storage/` | 历史 JSON、设置、DPAPI 凭据保护 |
| `lib/sync/` | mDNS 发布、mDNS/UDP 发现、广播节奏、TCP 帧、加密和同步编排 |
| `lib/view_models/` | 历史页搜索与操作代理 |
| `lib/views/` | 历史、悬停详情、同步、设置和翻译 UI |

```text
Flutter Clipboard API (500ms poll)
  → ClipboardMonitor
  → PrivacyGuard
  → ClipboardStore (ChangeNotifier singleton)
  → PersistenceController
  → ClipboardListViewModel / Provider
  → Widgets
```

## 数据与安全

| 数据 | macOS | Windows |
|---|---|---|
| 历史 JSON | `~/Library/Application Support/ClipboardManager/clipboard_history.json` | `%APPDATA%\ClipboardManager\clipboard_history.json` |
| 图片 | `~/Library/Application Support/ClipboardManager/Images/` | 尚未自动采集 |
| 普通设置 | `UserDefaults` | `SharedPreferences` |
| API Key / 同步 PIN | Keychain | DPAPI 加密后存入 `SharedPreferences` |
| 同步派生密钥 | 仅当前同步操作的内存 | 仅当前同步操作的内存 |

历史 JSON 本身不加密，因此不应记录密码等敏感内容。同步密钥由 PIN 和双方设备 ID 即时派生，不序列化、不持久化。同步安全边界见[同步协议](sync-protocol.md)。

## 关键设计决策

- macOS 列表使用 `ScrollView + LazyVStack`，避免浮动面板内 `List/NSTableView` 的约束问题。
- 条目详情延迟 350ms 展示，移出 150ms 后关闭，避免快速扫过列表时闪烁。
- 跨端只同步文本；图片和文件保持本机数据。
- 收到的同步条目通过同一 `ClipboardStore` 进入 UI 和持久化。
- 两端同步接收策略一致：按 UUID 去重、取消置顶、使用接收时间并在来源前加同步标记，写入后再回复 ACK；拒绝时回复带原因码的 `error` 消息。详见[同步协议](sync-protocol.md)。

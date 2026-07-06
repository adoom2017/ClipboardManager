# Copilot Instructions — macOS

统一文档位于工作区 `../docs/`；优先阅读 `../docs/architecture.md`、`../docs/development.md` 和 `../docs/sync-protocol.md`。

macOS 客户端红线：

- 工程结构由 `project.yml` 和 XcodeGen 管理，不手工编辑 `.xcodeproj`。
- 历史状态通过 `ClipboardStore.shared` 共享；测试使用内存持久化，不能触碰真实历史。
- `MenuBarExtra` 内的历史列表使用 `ScrollView + LazyVStack`，不要换回 SwiftUI `List`。
- 普通设置存 `UserDefaults`；API Key 与同步 PIN 存 Keychain。
- 同步只接受 `encryptedPayload`，协议变化必须同步 Windows 客户端和 `../docs/sync-protocol.md`。
- 构建与测试命令以 `../docs/development.md` 为准，测试 scheme 是 `ClipboardManager`。

# Clipboard Manager for macOS

SwiftUI + AppKit 菜单栏剪贴板管理器，是 `clipboard` 工作区的 macOS 客户端。

```bash
xcodegen generate
xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination 'platform=macOS' build
xcodebuild test -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination 'platform=macOS'
```

正式版打包：

```bash
./scripts/build-release.sh
```

产物位于 `build/Release/`。Developer ID 签名和公证参数见[开发指南](../docs/development.md#macos-打包)。

统一文档位于工作区根目录：

- [项目总览](../README.md)
- [用户指南](../docs/user-guide.md)
- [系统架构](../docs/architecture.md)
- [开发指南](../docs/development.md)
- [同步协议](../docs/sync-protocol.md)

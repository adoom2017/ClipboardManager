# ClipboardManager

ClipboardManager 是一个基于 SwiftUI 和 AppKit 的 macOS 菜单栏剪贴板管理器，支持保存和搜索剪贴板历史，并快速粘贴文本、图片和文件。

主要功能：

- 通过菜单栏图标或全局快捷键唤出历史面板
- 默认快捷键为 `Option + V`，可在设置中修改
- 支持剪贴板历史、隐私保护、开机启动和局域网同步
- 支持通过 OpenAI 兼容接口进行翻译

## 使用

### 环境要求

- macOS 14.0 或更高版本
- Xcode 15.0 或更高版本
- XcodeGen

### 构建和运行

1. 用 Xcode 打开 `ClipboardManager.xcodeproj`，选择 `ClipboardManager` scheme 后运行。
2. 如果项目文件不存在或需要重新生成，执行：

   ```bash
   xcodegen generate
   ```

3. 使用命令行构建和测试：

   ```bash
   xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager \
     -destination 'platform=macOS' build

   xcodebuild test -project ClipboardManager.xcodeproj -scheme ClipboardManager \
     -destination 'platform=macOS'
   ```

### 首次使用

- 应用启动后常驻菜单栏，点击菜单栏图标或按 `Option + V` 打开历史面板。
- 自动粘贴需要辅助功能权限。请在“系统设置 > 隐私与安全性 > 辅助功能”中允许 ClipboardManager，然后重新启动应用。
- 在设置中可以调整历史记录数量和保留天数、修改快捷键、开启隐私保护和开机启动。
- 使用翻译功能前，在“设置 > 翻译”中填写 OpenAI 兼容接口地址、API Key 和模型。

## 发布构建

构建带有签名校验的 Release 应用和 ZIP：

```bash
./scripts/build-release.sh
```

构建 Developer ID 签名 DMG：

```bash
./scripts/build-dmg-release.sh
```

产物默认位于 `build/Release/`。DMG 脚本需要可用的 Developer ID Application 证书；如证书不唯一，可通过 `SIGNING_IDENTITY` 和 `DEVELOPMENT_TEAM` 指定签名身份。设置 `NOTARY_PROFILE` 后，脚本还会执行公证和 stapling。

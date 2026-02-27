# ClipboardManager 项目文档

> 供 AI 开发助手使用的项目总结，快速上手时请先阅读此文档。

---

## 项目概述

**ClipboardManager** 是一个 macOS 菜单栏剪贴板管理应用，基于 SwiftUI + AppKit 构建，支持：
- 实时监控剪贴板变化
- 历史记录管理与搜索
- 全局快捷键调起 / 智能粘贴
- 隐私保护（屏蔽密码管理器内容）
- 固定（Pin）常用条目

**平台要求**：macOS 14.0+，Xcode 15，Swift 5.9  
**Bundle ID**：`com.clipboard.ClipboardManager`  
**版本**：1.0.0  
**项目配置工具**：[XcodeGen](https://github.com/yonaskolb/XcodeGen)（配置文件 `project.yml`）

---

## 技术架构

### 整体模式
- **架构**：MVVM（Model-View-ViewModel）+ 单例服务层
- **UI 框架**：SwiftUI（主体）+ AppKit（菜单栏、浮动面板）
- **数据持久化**：JSON 文件（无 Core Data）
- **响应式通信**：Combine（Publisher / Subscriber）
- **剪贴板访问**：`NSPasteboard`
- **全局快捷键**：Carbon Events API

### 目录结构

```
ClipboardManager/
├── App/                    # 应用入口 & 生命周期
│   ├── ClipboardManagerApp.swift   # @main SwiftUI App
│   └── AppDelegate.swift           # NSApplicationDelegate
├── Core/                   # 核心服务（单例）
│   ├── ClipboardMonitor.swift      # 剪贴板轮询监控
│   ├── AutoPasteService.swift      # 自动粘贴服务
│   └── PrivacyGuard.swift          # 隐私保护过滤
├── Models/
│   └── ClipboardItem.swift         # 数据模型
├── Storage/
│   ├── ClipboardStore.swift        # 内存存储 + CRUD
│   └── PersistenceController.swift # JSON 序列化/反序列化
├── ViewModels/
│   ├── ClipboardListViewModel.swift
│   └── SettingsViewModel.swift
├── Views/
│   ├── MenuBarView.swift           # 主容器视图（350×450）
│   ├── ClipboardListView.swift     # 列表视图
│   ├── ClipboardRowView.swift      # 行视图
│   ├── SearchBarView.swift         # 搜索栏
│   ├── PreviewPopover.swift        # 内容预览（备用）
│   └── SettingsView.swift          # 设置面板（含快捷键录制）
├── Extensions/
│   ├── NSPasteboard+Extensions.swift
│   └── String+Extensions.swift
├── Utilities/
│   ├── Constants.swift             # 全局常量
│   ├── KeyboardShortcutManager.swift  # 全局快捷键管理
│   └── FloatingPanelController.swift  # 浮动窗口管理
└── Resources/
    ├── Info.plist
    └── ClipboardManager.entitlements
```

---

## 核心模块详解

### 数据模型 `ClipboardItem`
```swift
struct ClipboardItem: Identifiable, Codable, Equatable {
    var id: UUID
    var content: String       // 剪贴板文字内容
    var timestamp: Date       // 记录时间
    var sourceApp: String     // 来源应用名称
    var isPinned: Bool        // 是否固定
    
    // 计算属性
    var contentPreview: String   // 前2行，最多100字符
    var relativeTimeString: String  // "2 minutes ago"
}
```

### 剪贴板监控 `ClipboardMonitor`（单例）
- 每 **0.5 秒**轮询 `NSPasteboard.general.changeCount`
- 检测到变化后调用 `PrivacyGuard` 过滤，通过则存入 `ClipboardStore`
- 通过 `@Published` 属性驱动 UI 更新

### 存储层 `ClipboardStore`（单例）
- 内存中维护 `[ClipboardItem]`，固定条目排在前面
- 每次变更后调用 `PersistenceController.saveItems()`
- 存储路径：`~/Library/Application Support/ClipboardManager/clipboard_history.json`
- 超出 `maxHistoryCount`（默认 100）自动删除最旧未固定条目
- `clearAllItems()` 只清除未固定条目

### 自动粘贴 `AutoPasteService`（单例）
- 记录上一个前台应用
- 粘贴流程：写入剪贴板 → 关闭 UI → 激活目标应用 → 模拟 Cmd+V
- 主方案：`CGEvent`（需要辅助功能权限）
- 备用方案：`AppleScript`
- 无权限时弹出提示引导用户授权

### 隐私保护 `PrivacyGuard`
屏蔽来源（源应用匹配，不区分大小写）：
- 1Password, Keychain, LastPass, Bitwarden 等密码管理器

内容模式检测（包含以下关键词则屏蔽）：
- `password`, `secret`, `token`, `api_key`, `private_key`

### 全局快捷键 `KeyboardShortcutManager`（单例）
- 默认快捷键：**⌥V**（Option + V）
- 使用 Carbon API 注册全局热键
- 支持用户自定义录制，持久化存储到 `UserDefaults`
- 热键触发 `FloatingPanelController.togglePanel()`

### 浮动面板 `FloatingPanelController`（单例）
- 基于 `NSPanel`，大小 **350×450**，居中显示
- `canBecomeKey = true`（支持搜索输入）
- `canBecomeMain = false`（不激活应用）
- 失焦后自动隐藏

---

## ViewModel 层

### `ClipboardListViewModel`
- 维护 `clipboardItems` 和 `searchText`
- `filteredItems`：根据 `searchText` 大小写不敏感过滤
- 通过 Combine 订阅 `ClipboardMonitor.newClipboardContent`

### `SettingsViewModel`
所有设置自动同步到 `UserDefaults`：

| 属性 | 默认值 | 说明 |
|------|--------|------|
| `maxHistoryCount` | 100 | 最大历史条数（10-500） |
| `retainDuration` | 7 | 保留天数（1-365） |
| `isClipboardHistoryEnabled` | true | 是否启用历史记录 |
| `isPrivacyGuardEnabled` | true | 是否启用隐私保护 |
| `isPrivacyModeEnabled` | false | 隐私模式 |

---

## UI 结构

```
MenuBarExtra（菜单栏图标）
└── MenuBarView（350×450）
    ├── SearchBarView（搜索框，40px高）
    ├── ClipboardListView（滚动列表）
    │   └── ClipboardRowView × N
    │       ├── 固定图标（橙色，仅固定条目显示）
    │       ├── 内容预览（最多2行）
    │       ├── 来源应用 + 相对时间
    │       └── 快捷键徽章（⌘1-⌘9，前9条）
    └── 底部工具栏
        ├── Clear History 按钮
        ├── 设置齿轮图标 → SettingsView
        └── 电源按钮（开关监控）

SettingsView（420×300，独立窗口）
├── Tab 1: General（历史条数、保留天数、清除）
├── Tab 2: Shortcut（快捷键录制）
└── Tab 3: Privacy（隐私保护开关）
```

### 列表交互
- 点击条目 → 自动粘贴
- 右键菜单：Pin/Unpin、Paste as Plain Text、Delete
- 滑动删除（Swipe to Delete）
- **⌘1-⌘9**：快速粘贴前 9 条

---

## 单元测试

位于 `ClipboardManagerTests/`：
- `ClipboardMonitorTests.swift`
- `ClipboardStoreTests.swift`
- `PrivacyGuardTests.swift`

---

## 常量一览（`Constants.swift`）

```swift
appName = "Clipboard Manager"
maxHistoryItems = 100
maxHistoryDays = 7
defaultSearchPlaceholder = "Search..."
// Notification names
clipboardItemDeletedNotification
// ...
```

---

## 已知设计决策 & 注意事项

1. **无 Core Data**：数据层完全使用 JSON 文件，路径固定，修改持久化逻辑只需改 `PersistenceController`。
2. **单例模式**：`ClipboardMonitor`、`ClipboardStore`、`AutoPasteService`、`FloatingPanelController`、`KeyboardShortcutManager` 均为单例，跨模块共享状态时直接使用 `.shared`。
3. **辅助功能权限**：自动粘贴功能依赖 macOS 辅助功能权限（Accessibility），首次使用需引导用户授权。
4. **代码签名**：`CODE_SIGNING_ALLOWED: false`，本地开发无需签名证书。
5. **`PreviewPopover`**：已实现但当前 UI 中未使用，可按需集成。
6. **轮询间隔**：剪贴板监控为 0.5 秒轮询（非系统推送），若需降低 CPU 占用可调整此值。
7. **XcodeGen**：修改项目配置请编辑 `project.yml`，然后运行 `xcodegen generate` 重新生成 `.xcodeproj`。

---

## 快速开发指引

### 添加新功能
- **新 UI 组件**：在 `Views/` 新增 SwiftUI View，通过 `ClipboardListViewModel` 获取数据
- **新设置项**：在 `SettingsViewModel` 添加 `@Published` 属性（自动持久化到 UserDefaults），在 `SettingsView` 添加对应控件
- **扩展数据模型**：修改 `ClipboardItem.swift`（注意 `Codable` 兼容性，添加默认值避免解码旧数据失败）
- **新剪贴板内容类型**：扩展 `NSPasteboard+Extensions.swift` 和 `ClipboardMonitor.getClipboardContent()`

### 修改快捷键逻辑
编辑 `KeyboardShortcutManager.swift`，Carbon API 注册在 `registerGlobalShortcut()`

### 修改自动粘贴行为
编辑 `AutoPasteService.swift`，主路径 `autoPaste()` → `pasteViaCGEvent()`，备用 `pasteViaAppleScript()`

### 调整隐私屏蔽规则
编辑 `PrivacyGuard.swift` 中的应用列表和内容关键词列表

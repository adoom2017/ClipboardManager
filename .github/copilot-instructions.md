# Copilot Instructions

## Build & Test

**Regenerate Xcode project** (after editing `project.yml`):
```bash
xcodegen generate
```

**Build from command line:**
```bash
xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -configuration Debug build
```

**Run all tests:**
```bash
xcodebuild test -project ClipboardManager.xcodeproj -scheme ClipboardManagerTests -destination 'platform=macOS'
```

**Run a single test:**
```bash
xcodebuild test -project ClipboardManager.xcodeproj -scheme ClipboardManagerTests -destination 'platform=macOS' -only-testing:ClipboardManagerTests/ClipboardStoreTests
```

**Requirements:** macOS 14.0+, Xcode 15, Swift 5.9

## Architecture

MVVM + singleton service layer. SwiftUI handles all views; AppKit handles the menu bar (`MenuBarExtra`) and floating panel (`NSPanel`).

```
App/          → @main SwiftUI entry + NSApplicationDelegate
Core/         → Singleton services (monitor, paste, privacy)
Models/       → ClipboardItem (Codable struct)
Storage/      → In-memory store + JSON persistence
ViewModels/   → ClipboardListViewModel, SettingsViewModel
Views/        → SwiftUI views
Utilities/    → Constants, global hotkey (Carbon API), floating panel
Extensions/   → NSPasteboard+, String+
```

Data flow: `ClipboardMonitor` polls `NSPasteboard` every 0.5s → filters via `PrivacyGuard` → stores in `ClipboardStore` → Combine publishers drive `ClipboardListViewModel` → SwiftUI re-renders.

Persistence: JSON at `~/Library/Application Support/ClipboardManager/clipboard_history.json` — no Core Data.

## Key Conventions

**Project configuration via XcodeGen:** Never edit `.xcodeproj` directly. All project structure changes go in `project.yml`, then run `xcodegen generate`.

**Singletons accessed via `.shared`:** `ClipboardMonitor.shared`, `ClipboardStore.shared`, `AutoPasteService.shared`, `FloatingPanelController.shared`, `KeyboardShortcutManager.shared`.

**Code signing disabled:** `CODE_SIGNING_ALLOWED: false` and `CODE_SIGN_IDENTITY: "-"` — no certificates needed for local development.

**Adding settings:** Add `@Published` property to `SettingsViewModel` (auto-syncs to `UserDefaults`), then add the corresponding control in `SettingsView`.

**Extending the data model:** Always add default values to new `ClipboardItem` properties to maintain `Codable` backward compatibility with persisted JSON.

**Auto-paste flow:** `AutoPasteService.autoPaste()` → primary: `CGEvent` (requires Accessibility permission) → fallback: AppleScript. Missing permission triggers a user-facing authorization prompt.

**Global hotkey:** Registered via Carbon Events API in `KeyboardShortcutManager.registerGlobalShortcut()`. Default: ⌥V. Custom shortcuts persisted to `UserDefaults`.

**Panel behavior:** `FloatingPanelController` uses `NSPanel` with `canBecomeKey = true` (allows search input) and `canBecomeMain = false` (doesn't steal app focus). Auto-hides on blur.

**Privacy filtering:** `PrivacyGuard` blocks by source app name (case-insensitive) and content keywords (`password`, `secret`, `token`, `api_key`, `private_key`). Edit blocklists directly in `PrivacyGuard.swift`.

**`PreviewPopover`** is implemented but not wired into any view — available for integration.

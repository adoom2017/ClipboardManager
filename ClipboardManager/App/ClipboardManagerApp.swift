import SwiftUI

@main
struct ClipboardManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = ClipboardListViewModel()
    @StateObject private var settingsViewModel = SettingsViewModel()

    var body: some Scene {
        // 菜单栏图标和弹出面板
        MenuBarExtra {
            MenuBarExtraContent(viewModel: viewModel)
        } label: {
            Image(systemName: "doc.on.clipboard")
                .imageScale(.large)
        }
        .menuBarExtraStyle(.window)

        // 设置窗口
        Settings {
            SettingsView(viewModel: settingsViewModel)
        }
    }
}

/// 包裹 MenuBarView，持有 openSettings 环境值并响应通知
private struct MenuBarExtraContent: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var viewModel: ClipboardListViewModel

    var body: some View {
        MenuBarView(clipboardListViewModel: viewModel)
            .frame(width: 350, height: 450)
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequest)) { _ in
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
    }
}
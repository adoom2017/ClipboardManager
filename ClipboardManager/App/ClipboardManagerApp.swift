import SwiftUI

@main
struct ClipboardManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settingsViewModel = SettingsViewModel()

    var body: some Scene {
        Settings {
            SettingsView(viewModel: settingsViewModel)
        }
    }
}

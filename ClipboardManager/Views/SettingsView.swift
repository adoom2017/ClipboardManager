import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var syncViewModel = SyncViewModel()
    @ObservedObject var shortcutManager = KeyboardShortcutManager.shared

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("通用", systemImage: "gear")
                }

            shortcutTab
                .tabItem {
                    Label("快捷键", systemImage: "keyboard")
                }

            privacyTab
                .tabItem {
                    Label("隐私", systemImage: "lock.shield")
                }

            translationTab

            SyncView(viewModel: syncViewModel)
                .tabItem {
                    Label("同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .tabItem {
                    Label("翻译", systemImage: "globe")
                }
        }
        .frame(width: 420, height: 360)
    }

    // MARK: - 通用设置
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("启用剪贴板历史记录", isOn: $viewModel.isClipboardHistoryEnabled)

            HStack {
                Text("最大历史条数:")
                Spacer()
                Stepper("\(viewModel.maxHistoryCount)",
                        value: $viewModel.maxHistoryCount, in: 10...500, step: 10)
            }

            HStack {
                Text("保留天数:")
                Spacer()
                Stepper("\(viewModel.retainDuration) 天",
                        value: $viewModel.retainDuration, in: 1...365)
            }

            Divider()

            HStack {
                Button("清空所有历史") {
                    viewModel.clearHistory()
                }
                .foregroundColor(.red)

                Spacer()

                Button("重置设置") {
                    viewModel.resetSettings()
                }
            }
        }
        .padding(20)
    }

    // MARK: - 快捷键设置
    private var shortcutTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("全局快捷键")
                .font(.headline)

            Text("按下快捷键可以在任何应用中唤出剪贴板历史面板")
                .font(.callout)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Text("唤出历史记录:")

                // 快捷键录制按钮
                ShortcutRecorderView(shortcutManager: shortcutManager)

                Button("恢复默认") {
                    shortcutManager.resetToDefault()
                }
                .font(.caption)
            }

            Spacer()

            Text("提示: 默认快捷键为 ⌥V (Option + V)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
    }

    // MARK: - 隐私设置
    private var privacyTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("启用隐私保护", isOn: $viewModel.isPrivacyGuardEnabled)

            Text("开启后，来自 1Password、钥匙串访问等密码管理器的剪贴板内容将不被记录。")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(20)
    }

    // MARK: - 翻译设置
    private var translationTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("使用 OpenAI 兼容接口进行翻译，支持 OpenAI、DeepSeek、Groq、Ollama 等。")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("API 地址:")
                        .gridColumnAlignment(.trailing)
                    TextField("https://api.openai.com/v1", text: $viewModel.translationAPIURL)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("API Key:")
                        .gridColumnAlignment(.trailing)
                    SecureField("sk-...", text: $viewModel.translationAPIKey)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("模型:")
                        .gridColumnAlignment(.trailing)
                    TextField("gpt-4o-mini", text: $viewModel.translationModel)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text("示例：DeepSeek → https://api.deepseek.com/v1，模型 deepseek-chat\nGemini → https://generativelanguage.googleapis.com/v1beta，模型 gemini-2.0-flash")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(20)
    }
}

// MARK: - 快捷键录制控件

struct ShortcutRecorderView: View {
    @ObservedObject var shortcutManager: KeyboardShortcutManager

    var body: some View {
        Button(action: {
            if shortcutManager.isRecording {
                shortcutManager.stopRecording()
                // 重新注册当前快捷键
            } else {
                shortcutManager.startRecording()
            }
        }) {
            HStack(spacing: 6) {
                if shortcutManager.isRecording {
                    Image(systemName: "record.circle")
                        .foregroundColor(.red)
                    Text("请按下新快捷键...")
                        .foregroundColor(.red)
                } else {
                    Text(shortcutManager.currentShortcut.displayString)
                        .fontWeight(.medium)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minWidth: 120)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(shortcutManager.isRecording
                          ? Color.red.opacity(0.1)
                          : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(shortcutManager.isRecording
                            ? Color.red.opacity(0.5)
                            : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(viewModel: SettingsViewModel())
    }
}
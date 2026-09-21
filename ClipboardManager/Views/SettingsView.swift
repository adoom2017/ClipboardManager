import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var syncViewModel = SyncViewModel()
    @ObservedObject var shortcutManager = KeyboardShortcutManager.shared
    @State private var showLaunchAtLoginError = false

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
                .tabItem {
                    Label("翻译", systemImage: "globe")
                }

            SyncView(viewModel: syncViewModel, settingsViewModel: viewModel)
                .tabItem {
                    Label("同步", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .frame(width: 420, height: 360)
        .glassBackdrop()
        .background(.ultraThinMaterial)
        .alert("无法更新开机启动", isPresented: $showLaunchAtLoginError) {
            Button("确定") {
                viewModel.clearLaunchAtLoginError()
            }
        } message: {
            Text(viewModel.launchAtLoginErrorMessage ?? "请稍后重试。")
        }
        .onChange(of: viewModel.launchAtLoginErrorMessage) {
            showLaunchAtLoginError = viewModel.launchAtLoginErrorMessage != nil
        }
    }

    // MARK: - 通用设置
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingCard {
                Toggle("启用剪贴板历史记录", isOn: $viewModel.isClipboardHistoryEnabled)

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("开机时自动启动", isOn: $viewModel.launchAtLoginEnabled)
                    Text(viewModel.launchAtLoginHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingCard {
                settingStepper(title: "最大历史条数", value: "\(viewModel.maxHistoryCount)") {
                    Stepper("", value: $viewModel.maxHistoryCount, in: 10...500, step: 10)
                        .labelsHidden()
                }
                settingStepper(title: "保留天数", value: "\(viewModel.retainDuration) 天") {
                    Stepper("", value: $viewModel.retainDuration, in: 1...365)
                        .labelsHidden()
                }
            }

            HStack {
                Button("清空所有历史", role: .destructive) { viewModel.clearHistory() }
                Spacer()
                Button("重置设置") { viewModel.resetSettings() }
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
    }

    // MARK: - 快捷键设置
    private var shortcutTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingCard {
                Label("全局快捷键", systemImage: "keyboard")
                    .font(.headline)
                Text("按下快捷键可以在任何应用中唤出剪贴板历史面板")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text("唤出历史记录")
                    Spacer()
                    ShortcutRecorderView(shortcutManager: shortcutManager)
                    Button("恢复默认") { shortcutManager.resetToDefault() }
                        .font(.caption)
                }
            }

            Spacer()

            Text("提示: 默认快捷键为 ⌥V (Option + V)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    // MARK: - 隐私设置
    private var privacyTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingCard {
                Toggle("启用隐私保护", isOn: $viewModel.isPrivacyGuardEnabled)
                Text("开启后，来自 1Password、钥匙串访问等密码管理器的剪贴板内容将不被记录。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(20)
    }

    // MARK: - 翻译设置
    private var translationTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingCard {
                Text("使用 OpenAI 兼容接口进行翻译，支持 OpenAI、DeepSeek、Groq、Ollama 等。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                settingField("API 地址", placeholder: "https://api.openai.com/v1", text: $viewModel.translationAPIURL)
                settingField("API Key", placeholder: "sk-...", text: $viewModel.translationAPIKey, secure: true)
                settingField("模型", placeholder: "gpt-4o-mini", text: $viewModel.translationModel)

                Text("示例：DeepSeek → https://api.deepseek.com/v1，模型 deepseek-chat\nGemini → https://generativelanguage.googleapis.com/v1beta，模型 gemini-2.0-flash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
    }

    private func settingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelSectionSurface(cornerRadius: 15, fillOpacity: 0.30)
    }

    private func settingStepper<Control: View>(title: String, value: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            control()
        }
    }

    private func settingField(_ title: String, placeholder: String, text: Binding<String>, secure: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(.secondary)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.roundedBorder)
        }
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
            .adaptiveGlassSurface(cornerRadius: 8, prominent: shortcutManager.isRecording, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(viewModel: SettingsViewModel())
    }
}

import SwiftUI

struct TranslationWindowView: View {
    let originalText: String
    @State private var translatedText: String = ""
    @State private var direction: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var copyFeedback: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // 语言方向 + loading 指示条（标题栏已显示"翻译"，这里只显示方向）
            if !direction.isEmpty || isLoading {
                HStack(spacing: 6) {
                    if !direction.isEmpty {
                        Image(systemName: "globe")
                            .foregroundColor(.accentColor)
                            .font(.caption)
                        Text(direction)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.65)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
            }

            // 原文
            VStack(alignment: .leading, spacing: 6) {
                Text("原文")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                ScrollView {
                    Text(originalText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .textSelection(.enabled)
                }
                .frame(height: 100)
                .background(Color(nsColor: .controlBackgroundColor))
            }

            Divider()

            // 译文
            VStack(alignment: .leading, spacing: 6) {
                Text("译文")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                if let error = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                } else if isLoading && translatedText.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("翻译中...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .frame(height: 100)
                } else {
                    ScrollView {
                        Text(translatedText.isEmpty ? " " : translatedText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                            .textSelection(.enabled)
                    }
                    .frame(height: 100)
                }
            }

            Divider()

            // 底部操作栏
            HStack {
                Button(action: retranslate) {
                    Label("重新翻译", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .disabled(isLoading)

                Spacer()

                Button(action: copyTranslation) {
                    Label(copyFeedback ? "已复制" : "复制译文", systemImage: copyFeedback ? "checkmark" : "doc.on.doc")
                        .font(.callout)
                }
                .buttonStyle(.borderedProminent)
                .disabled(translatedText.isEmpty || isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 420)
        .task {
            await performTranslation()
        }
    }

    private func performTranslation() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await TranslationService.shared.translate(originalText)
            translatedText = result.result
            direction = result.direction
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func retranslate() {
        translatedText = ""
        direction = ""
        Task { await performTranslation() }
    }

    private func copyTranslation() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translatedText, forType: .string)
        withAnimation {
            copyFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copyFeedback = false }
        }
    }
}

import SwiftUI

struct TranslationWindowView: View {
    let originalText: String
    @State private var translatedText = ""
    @State private var direction = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var copyFeedback = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.1), .clear, Color.indigo.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 12) {
                    translationContent
                }
            } else {
                translationContent
            }
        }
        .background(.ultraThinMaterial)
        .frame(width: 420, height: 400)
        .task {
            await performTranslation()
        }
    }

    private var translationContent: some View {
        VStack(spacing: 12) {
            statusHeader
            textCard(title: "原文", systemImage: "text.quote", text: originalText)
            translationCard
            actionBar
        }
        .padding(14)
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe.asia.australia.fill")
                .foregroundStyle(.tint)
            Text(direction.isEmpty ? "智能翻译" : direction)
                .font(.headline)
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .opacity(translatedText.isEmpty ? 0 : 1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .adaptiveGlassSurface(cornerRadius: 13)
    }

    private func textCard(title: String, systemImage: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                Text(text)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 112, alignment: .topLeading)
        .adaptiveGlassSurface(cornerRadius: 14)
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("译文", systemImage: "character.bubble")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Group {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if isLoading && translatedText.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在生成翻译…")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(translatedText.isEmpty ? " " : translatedText)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 132, alignment: .topLeading)
        .adaptiveGlassSurface(cornerRadius: 14, prominent: true)
    }

    @ViewBuilder
    private var actionBar: some View {
        let content = HStack {
            Button(action: retranslate) {
                Label("重新翻译", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)

            Spacer()

            Button(action: copyTranslation) {
                Label(
                    copyFeedback ? "已复制" : "复制译文",
                    systemImage: copyFeedback ? "checkmark" : "doc.on.doc"
                )
            }
            .disabled(translatedText.isEmpty || isLoading)
        }
        .font(.callout)

        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.glass)
        } else {
            content
                .buttonStyle(.bordered)
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
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            copyFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                copyFeedback = false
            }
        }
    }
}

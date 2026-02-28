import Foundation

/// 翻译服务，支持 OpenAI 兼容接口（OpenAI / DeepSeek / Groq / Ollama 等）及 Google Gemini
class TranslationService {
    static let shared = TranslationService()
    private init() {}

    enum TranslationError: LocalizedError {
        case notConfigured
        case networkError(Error)
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "请先在设置中配置翻译 API"
            case .networkError(let e):
                return "网络错误：\(e.localizedDescription)"
            case .invalidResponse:
                return "API 返回格式异常"
            case .apiError(let msg):
                return "API 错误：\(msg)"
            }
        }
    }

    // MARK: - 语言检测

    /// 判断文本是否以中文为主
    func isMajorityChinese(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        let chineseCount = scalars.filter { isCJK($0) }.count
        let letterCount = scalars.filter { $0.value >= 0x41 && $0.value <= 0x7A || isCJK($0) }.count
        guard letterCount > 0 else { return false }
        return Double(chineseCount) / Double(letterCount) > 0.3
    }

    private func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (v >= 0x4E00 && v <= 0x9FFF)   // CJK 基本区
            || (v >= 0x3400 && v <= 0x4DBF)   // CJK 扩展 A
            || (v >= 0x20000 && v <= 0x2A6DF) // CJK 扩展 B
            || (v >= 0xF900 && v <= 0xFAFF)   // CJK 兼容
    }

    private func isGemini(_ baseURL: String) -> Bool {
        baseURL.contains("generativelanguage.googleapis.com")
    }

    // MARK: - 翻译入口

    /// 翻译文本，自动检测方向：中文→英文，英文/其他→中文
    func translate(_ text: String) async throws -> (result: String, direction: String) {
        let apiURL = UserDefaults.standard.string(forKey: "translationAPIURL") ?? ""
        let apiKey = UserDefaults.standard.string(forKey: "translationAPIKey") ?? ""
        let model = UserDefaults.standard.string(forKey: "translationModel") ?? "gpt-4o-mini"

        guard !apiURL.isEmpty, !apiKey.isEmpty else {
            throw TranslationError.notConfigured
        }

        let isChinese = isMajorityChinese(text)
        let direction = isChinese ? "中文 → English" : "English → 中文"
        let systemPrompt = isChinese
            ? "You are a professional translator. Translate the following Chinese text to English. Output only the translation, no explanations."
            : "你是一名专业翻译。将以下英文文本翻译成中文。只输出翻译结果，不要解释。"

        let baseURL = apiURL.hasSuffix("/") ? String(apiURL.dropLast()) : apiURL

        let result: String
        if isGemini(baseURL) {
            result = try await translateViaGemini(text: text, systemPrompt: systemPrompt,
                                                  baseURL: baseURL, apiKey: apiKey, model: model)
        } else {
            result = try await translateViaOpenAI(text: text, systemPrompt: systemPrompt,
                                                  baseURL: baseURL, apiKey: apiKey, model: model)
        }
        return (result, direction)
    }

    // MARK: - OpenAI 兼容

    private func translateViaOpenAI(text: String, systemPrompt: String,
                                    baseURL: String, apiKey: String, model: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw TranslationError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3,
            "max_tokens": 2000
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorBody["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw TranslationError.apiError(message)
            }
            throw TranslationError.apiError("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslationError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Gemini

    private func translateViaGemini(text: String, systemPrompt: String,
                                    baseURL: String, apiKey: String, model: String) async throws -> String {
        // Gemini endpoint: {baseURL}/models/{model}:generateContent?key={apiKey}
        let endpoint = "\(baseURL)/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else {
            throw TranslationError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                ["parts": [["text": text]]]
            ],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 2000
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errArr = errorBody["error"] as? [String: Any],
               let message = errArr["message"] as? String {
                throw TranslationError.apiError(message)
            }
            throw TranslationError.apiError("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw TranslationError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

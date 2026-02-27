import Foundation

extension String {
    /// 去除富文本格式，返回纯文本
    var plainText: String {
        return self
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 截取摘要
    func truncated(to maxLength: Int = 100) -> String {
        if self.count <= maxLength {
            return self
        }
        return String(self.prefix(maxLength)) + "…"
    }
}
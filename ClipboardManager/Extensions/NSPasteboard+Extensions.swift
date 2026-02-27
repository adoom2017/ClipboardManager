import Cocoa

extension NSPasteboard {
    /// 获取当前字符串内容
    func getCurrentString() -> String? {
        return string(forType: .string)
    }

    /// 设置字符串到剪贴板
    func setClipboardString(_ string: String) {
        clearContents()
        setString(string, forType: .string)
    }

    /// 检查剪贴板是否包含字符串
    func containsString() -> Bool {
        return availableType(from: [.string]) != nil
    }

    /// 获取当前图片内容
    func getCurrentImage() -> NSImage? {
        guard let objects = readObjects(forClasses: [NSImage.self], options: nil) else {
            return nil
        }
        return objects.first as? NSImage
    }

    /// 设置图片到剪贴板
    func setClipboardImage(_ image: NSImage) {
        clearContents()
        if let tiffData = image.tiffRepresentation {
            setData(tiffData, forType: .tiff)
        }
    }

    /// 获取文件 URLs（仅限本地文件，非 http 链接）
    func getCurrentFileURLs() -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let objects = readObjects(forClasses: [NSURL.self], options: options) as? [URL],
            !objects.isEmpty
        else { return nil }
        return objects
    }

    /// 将文件 URLs 写入剪贴板
    func setClipboardFileURLs(_ urls: [URL]) {
        clearContents()
        writeObjects(urls as [NSURL])
    }
}

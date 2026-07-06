import Cocoa

extension NSPasteboard {
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

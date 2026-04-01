import Foundation

enum AppLogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warn = 2
    case error = 3

    var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }

    static func < (lhs: AppLogLevel, rhs: AppLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

final class AppLogger {
    static let shared = AppLogger()

    private let queue = DispatchQueue(label: "com.clipboard.logger")
    private let minimumLevel: AppLogLevel = .info
    private let maxFileSizeBytes = 1_024 * 1_024
    private let maxTotalSizeBytes = 20 * 1_024 * 1_024
    private let retentionInterval: TimeInterval = 7 * 24 * 60 * 60
    private let logFileName = "app.log"

    private var logsDirectoryURL: URL?
    private var cleanupTimer: DispatchSourceTimer?
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    func start() {
        queue.async {
            self.prepareLocked()
            self.cleanupLocked()
            self.scheduleCleanupLocked()
        }
    }

    func debug(_ category: String, _ message: String) {
        log(.debug, category, message)
    }

    func info(_ category: String, _ message: String) {
        log(.info, category, message)
    }

    func warn(_ category: String, _ message: String) {
        log(.warn, category, message)
    }

    func error(_ category: String, _ message: String) {
        log(.error, category, message)
    }

    func log(_ level: AppLogLevel, _ category: String, _ message: String) {
        guard level >= minimumLevel else { return }

        let line = "\(formatter.string(from: Date())) [\(level.label)] [\(category)] \(message)"
        print(line)

        queue.async {
            self.prepareLocked()
            self.writeLocked(line + "\n")
        }
    }

    private func prepareLocked() {
        if logsDirectoryURL != nil { return }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ClipboardManager", isDirectory: true)
        let logsDir = appDir.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        logsDirectoryURL = logsDir

        let currentLogURL = logsDir.appendingPathComponent(logFileName)
        if !FileManager.default.fileExists(atPath: currentLogURL.path) {
            FileManager.default.createFile(atPath: currentLogURL.path, contents: nil)
        }
    }

    private func writeLocked(_ line: String) {
        guard let logURL = currentLogURL else { return }
        let additionalBytes = line.lengthOfBytes(using: .utf8)
        rotateIfNeededLocked(forAdditionalBytes: additionalBytes)

        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }

    private var currentLogURL: URL? {
        logsDirectoryURL?.appendingPathComponent(logFileName)
    }

    private func rotateIfNeededLocked(forAdditionalBytes additionalBytes: Int) {
        guard let currentLogURL else { return }
        let currentSize = (try? FileManager.default.attributesOfItem(atPath: currentLogURL.path)[.size] as? NSNumber)?.intValue ?? 0
        guard currentSize + additionalBytes > maxFileSizeBytes else { return }

        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let rotatedURL = currentLogURL.deletingLastPathComponent()
            .appendingPathComponent("app-\(timestamp).log")
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: currentLogURL, to: rotatedURL)
        FileManager.default.createFile(atPath: currentLogURL.path, contents: nil)
        cleanupLocked()
    }

    private func scheduleCleanupLocked() {
        guard cleanupTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(24 * 60 * 60), repeating: .seconds(24 * 60 * 60))
        timer.setEventHandler { [weak self] in
            self?.cleanupLocked()
        }
        timer.resume()
        cleanupTimer = timer
    }

    private func cleanupLocked() {
        guard let logsDirectoryURL else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: logsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let now = Date()

        var files: [(url: URL, modified: Date, size: Int)] = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = values.contentModificationDate,
                  let size = values.fileSize else { return nil }
            return (url, modified, size)
        }

        for file in files where now.timeIntervalSince(file.modified) > retentionInterval {
            try? FileManager.default.removeItem(at: file.url)
        }

        files = files
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
            .sorted { $0.modified < $1.modified }

        var totalSize = files.reduce(0) { $0 + $1.size }
        for file in files where totalSize > maxTotalSizeBytes && file.url.lastPathComponent != logFileName {
            try? FileManager.default.removeItem(at: file.url)
            totalSize -= file.size
        }
    }
}

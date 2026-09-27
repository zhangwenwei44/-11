import Foundation
import SwiftUI

// MARK: - 日志级别

enum BeansLogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"

    var tint: Color {
        switch self {
        case .debug: return .secondary
        case .info: return .blue
        case .warn: return .orange
        case .error: return .red
        }
    }
}

// MARK: - 单条日志

struct BeansLogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let level: BeansLogLevel
    let message: String
}

// MARK: - 全局日志中心

/// 全局日志中心：内存环形缓存（供 App 内查看）+ 文件持久化（Documents/BeansLogs/beans-日期.log，可导出分享）。
/// 任意线程可调用 log()，界面更新自动切回主线程。
final class BeansLogger: ObservableObject {
    static let shared = BeansLogger()

    @Published private(set) var entries: [BeansLogEntry] = []

    private let maxEntries = 5000
    private let maxLogFileBytes = 10 * 1024 * 1024
    private let lock = NSLock()
    private var recentEntries: [BeansLogEntry] = []
    /// 落盘串行队列。日志可能在一秒内产生数十条（userPlaylists 每页一条），
    /// 逐行做 stat/open/seek/write/close 会把调用线程拖住，所以整体挪到后台串行执行。
    private let fileQueue = DispatchQueue(label: "com.beans.logger.file", qos: .utility)
    /// 内存队列，避免在锁内做逐条 dispatch 带来的额外分配。
    private var pendingEntries: [BeansLogEntry] = []

    private static let lineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
    private static let fileStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    private init() {
        log("Beans Music 启动（版本 \(Self.appVersion)）", level: .info)
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static func dateString(_ date: Date) -> String {
        lineFormatter.string(from: date)
    }

    /// 记录一条日志（任意线程可调用）
    func log(_ message: String, level: BeansLogLevel = .debug) {
        let entry = BeansLogEntry(date: Date(), level: level, message: message)
        lock.lock()
        recentEntries.append(entry)
        if recentEntries.count > maxEntries {
            recentEntries.removeFirst(recentEntries.count - maxEntries)
        }
        pendingEntries.append(entry)
        let batch = pendingEntries
        pendingEntries.removeAll(keepingCapacity: true)
        lock.unlock()
        // 批量合并后再更新 @Published：整条日志链路上只做一次主线程派发与一次数组追加，
        // 避免每行都把最多 5000 条复制到主线程。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.entries.append(contentsOf: batch)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
        fileQueue.async { [weak self] in
            guard let self else { return }
            for e in batch {
                self.write(e.line)
            }
        }
    }

    /// 全部日志文本（按时间正序）
    var fullText: String {
        lock.lock()
        let snapshot = recentEntries
        lock.unlock()
        return snapshot.map(\.line).joined(separator: "\n")
    }

    /// 清空内存日志与日志文件
    func clear() {
        lock.lock()
        recentEntries = []
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.entries = []
        }
        fileQueue.async { [weak self] in
            guard let self else { return }
            let dir = self.logDirectory
            self.lock.lock()
            // 目录已被删除，下次写入前必须重新解析。
            self.cachedLogDirectory = nil
            self.cachedFileURL = nil
            self.cachedFileStamp = nil
            self.lock.unlock()
            try? FileManager.default.removeItem(at: dir)
        }
        log("日志已清空", level: .info)
    }

    // MARK: - 文件持久化

    // 仅在 fileQueue 与导出路径访问，访问时用 lock 保护（lock 不可重入，勿嵌套调用）。
    private var cachedLogDirectory: URL?
    private var cachedFileURL: URL?
    private var cachedFileStamp: String?

    private var logDirectory: URL {
        lock.lock()
        defer { lock.unlock() }
        return resolvedLogDirectoryLocked()
    }

    private func resolvedLogDirectoryLocked() -> URL {
        if let cachedLogDirectory { return cachedLogDirectory }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeansLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cachedLogDirectory = dir
        return dir
    }

    private var currentFileURL: URL {
        let stamp = Self.fileStampFormatter.string(from: Date())
        lock.lock()
        defer { lock.unlock() }
        if let cachedFileURL, cachedFileStamp == stamp { return cachedFileURL }
        let url = resolvedLogDirectoryLocked().appendingPathComponent("beans-\(stamp).log")
        cachedFileStamp = stamp
        cachedFileURL = url
        return url
    }

    /// 导出日志文件（不存在则先生成一份完整日志）
    func exportLogURL() -> URL {
        // 落盘已改为异步，先等队列排空，保证导出文件包含最后几条日志。
        fileQueue.sync {}
        let url = currentFileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? fullText.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    /// 导出项：当日运行日志 + 全部崩溃日志 + 全部卡顿报告
    func exportItems() -> [URL] {
        [exportLogURL()]
            + BeansCrashHandler.shared.crashLogURLs()
            + BeansHangWatchdog.shared.hangLogURLs()
    }

    private func write(_ line: String) {
        let url = currentFileURL
        // 单日日志过大时轮转到 .1，避免无限膨胀
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        if fileSize > maxLogFileBytes {
            let rotated = url.deletingPathExtension().appendingPathExtension("1.log")
            try? FileManager.default.removeItem(at: rotated)
            try? FileManager.default.moveItem(at: url, to: rotated)
        }
        let payload = (line + "\n").data(using: .utf8) ?? Data()
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(payload)
        } else {
            try? payload.write(to: url, options: .atomic)
        }
    }
}

extension BeansLogEntry {
    var line: String {
        "[\(BeansLogger.dateString(date))] [\(level.rawValue)] \(message)"
    }
}

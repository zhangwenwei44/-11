import Foundation
import Darwin

/// 崩溃与致命信号捕获：把未捕获异常、致命信号写入 Documents/BeansLogs/crash-*.log。
/// 与运行日志同目录，导出日志时一并分享，便于离线分析崩溃原因。
final class BeansCrashHandler {
    static let shared = BeansCrashHandler()

    private static let capturedSignals: [Int32] = [SIGILL, SIGTRAP, SIGABRT, SIGFPE, SIGBUS, SIGSEGV]
    /// 安装时预生成 C 路径字符串；信号回调里只做索引与文件写入。
    private static var signalPaths: [UnsafeMutablePointer<CChar>?] = Array(repeating: nil, count: 6)
    private static var crashDirectoryPath: UnsafeMutablePointer<CChar>?

    private init() {}

    func install() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeansLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Self.crashDirectoryPath = strdup(dir.path)
        for (index, sig) in Self.capturedSignals.enumerated() {
            let path = dir.appendingPathComponent("crash-signal-\(sig).log").path
            Self.signalPaths[index] = strdup(path)
            _ = signal(sig, BeansCrashHandler.handleSignal)
        }
        NSSetUncaughtExceptionHandler { exception in
            BeansCrashHandler.recordUncaughtException(exception)
        }
    }

    /// 目录下全部崩溃日志（供导出分享）
    func crashLogURLs() -> [URL] {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeansLogs", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("crash-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - 未捕获异常（可安全使用 Swift 运行时）

    private static func recordUncaughtException(_ exception: NSException) {
        let text = """
        ==== uncaught exception \(Self.timestampString()) ====
        version: \(BeansLogger.appVersion)
        name: \(exception.name.rawValue)
        reason: \(exception.reason ?? "")
        \(exception.callStackSymbols.joined(separator: "\n"))

        """
        Self.append(path: Self.crashFilePath(), text: text)
        // 不回调 BeansLogger：若崩溃发生在其持锁期间会死锁，崩溃文件本身即记录。
    }

    // MARK: - 致命信号（async-signal-safe：只允许 C 调用与文件写入）

    private static let handleSignal: @convention(c) (Int32) -> Void = { sig in
        let index = BeansCrashHandler.capturedSignals.firstIndex(of: sig)
        let pathC = index.flatMap { BeansCrashHandler.signalPaths[$0] }
        if let pathC {
            let fd = open(pathC, O_WRONLY | O_CREAT | O_APPEND, 0o644)
            if fd >= 0 {
                var timeVal = time(nil)
                var localTm = tm()
                localtime_r(&timeVal, &localTm)
                var timeBuf = [CChar](repeating: 0, count: 64)
                strftime(&timeBuf, timeBuf.count, "%Y-%m-%d %H:%M:%S", &localTm)
                let header = "==== fatal signal \(sig) at \(String(cString: timeBuf)) ====\n"
                let headerBytes = Array(header.utf8)
                headerBytes.withUnsafeBufferPointer { ptr in
                    _ = write(fd, ptr.baseAddress, ptr.count)
                }
                var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
                let count = backtrace(&frames, Int32(frames.count))
                backtrace_symbols_fd(&frames, count, fd)
                close(fd)
            }
        }
        _ = signal(sig, SIG_DFL)
        _ = raise(sig)
    }

    // MARK: - 工具

    private static func crashFilePath() -> String {
        let base = crashDirectoryPath.map { String(cString: $0) } ?? NSTemporaryDirectory()
        return base + "/crash-exception-" + Self.fileStamp() + ".log"
    }

    private static func fileStamp() -> String {
        var timeVal = time(nil)
        var localTm = tm()
        localtime_r(&timeVal, &localTm)
        var buf = [CChar](repeating: 0, count: 32)
        strftime(&buf, buf.count, "%Y%m%d-%H%M%S", &localTm)
        return String(cString: buf)
    }

    private static func timestampString() -> String {
        var timeVal = time(nil)
        var localTm = tm()
        localtime_r(&timeVal, &localTm)
        var buf = [CChar](repeating: 0, count: 64)
        strftime(&buf, buf.count, "%Y-%m-%d %H:%M:%S", &localTm)
        return String(cString: buf)
    }

    private static func append(path: String, text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        data.withUnsafeBytes { raw in
            _ = write(fd, raw.baseAddress, raw.count)
        }
        close(fd)
    }
}

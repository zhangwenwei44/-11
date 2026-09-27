import Foundation
import Darwin

/// 主线程卡顿看门狗。
///
/// 崩溃有信号捕获，但「界面卡住几秒又不崩」这种问题此前完全不留痕迹——
/// 运行日志里没有对应条目，崩溃目录里也没有文件，事后无法定位。
/// 这里用一个 .strict 定时器挂在主队列上：定时器迟到即说明主线程被阻塞，
/// 恢复后立即抓取当时的调用栈写入 Documents/BeansLogs/hang-*.log。
///
/// 栈在「发现迟到」的那一刻抓取（而不是等下一轮），这样拿到的是真正卡住主线程
/// 的那个调用点，而不是恢复之后的空闲栈。抓栈与写盘都放到后台队列，
/// 避免看门狗自己成为新的卡顿源。
final class BeansHangWatchdog {
    static let shared = BeansHangWatchdog()

    /// 心跳间隔。250ms 足以发现肉眼可见的卡顿，又不会显著增加唤醒次数。
    private let tickInterval: TimeInterval = 0.25
    /// 超过该延迟判定为卡顿。留出一次心跳的容差，避免临界抖动误报。
    private let threshold: TimeInterval = 0.5
    /// 同一分钟内多次卡顿只记一次首现，避免把日志本身刷爆。
    private let reportCooldown: TimeInterval = 60

    private var timer: DispatchSourceTimer?
    private var expectedTick = Date.distantPast
    private var lastReportedAt = Date.distantPast
    private let stateLock = NSLock()
    /// 抓栈/写盘队列，与主线程分离。
    private let workQueue = DispatchQueue(label: "com.beans.hangwatchdog", qos: .utility)

    private init() {}

    func install() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard timer == nil else { return }

        // 基线必须从现在开始起算：若留作 distantPast，首个心跳会被误判成
        // 「卡了上百年」的假阳性。
        expectedTick = Date().addingTimeInterval(tickInterval)

        let t = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        t.schedule(deadline: .now() + tickInterval, repeating: tickInterval, leeway: .milliseconds(20))
        t.setEventHandler { [weak self] in
            self?.onTick()
        }
        timer = t
        t.resume()
    }

    private func onTick() {
        let now = Date()
        let expected = expectedTick
        // 无论本次是否迟到，都要重置基线，否则一次卡顿会让之后每拍都误报。
        expectedTick = now.addingTimeInterval(tickInterval)

        let delay = now.timeIntervalSince(expected)
        guard delay > threshold else { return }

        stateLock.lock()
        let shouldReport = now.timeIntervalSince(lastReportedAt) > reportCooldown
        if shouldReport { lastReportedAt = now }
        stateLock.unlock()
        guard shouldReport else { return }

        let delayMs = Int(delay * 1000)
        BeansLogger.shared.log("主线程卡顿 \(delayMs)ms，已抓取调用栈", level: .warn)
        // 抓栈必须在主线程（此刻主线程仍卡在原处），但符号化和写盘放后台。
        let symbols = Thread.callStackSymbols
        workQueue.async {
            Self.writeReport(delayMs: delayMs, symbols: symbols)
        }
    }

    private static func writeReport(delayMs: Int, symbols: [String]) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeansLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("hang-\(stamp()).log")
        let text = """
        ==== main thread hang \(stamp()) ====
        version: \(BeansLogger.appVersion)
        delay: \(delayMs)ms
        --- backtrace ---
        \(symbols.joined(separator: "\n"))

        """
        guard let data = text.data(using: .utf8) else { return }
        // O_APPEND 原子写，多张卡顿记录可以安全累积到同一秒的文件里。
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        data.withUnsafeBytes { raw in
            _ = write(fd, raw.baseAddress, raw.count)
        }
        close(fd)
    }

    private static func stamp() -> String {
        var timeVal = time(nil)
        var localTm = tm()
        localtime_r(&timeVal, &localTm)
        var buf = [CChar](repeating: 0, count: 32)
        strftime(&buf, buf.count, "%Y%m%d-%H%M%S", &localTm)
        return String(cString: buf)
    }

    /// 目录下的卡顿报告（随「查看与导出运行日志」一并分享）。
    func hangLogURLs() -> [URL] {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeansLogs", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("hang-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

import Foundation

/// テストが経過秒を手動で進められる時刻源です。
final class DevicesManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: TimeInterval

    /// 責務: 指定した経過秒から始まる時刻源を生成します。
    init(_ seconds: TimeInterval = 0) {
        self.seconds = seconds
    }

    /// 責務: 現在の経過秒を返します。
    func read() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return seconds
    }

    /// 責務: 経過秒を指定値へ設定します。
    func set(_ value: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        seconds = value
    }
}

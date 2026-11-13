import Foundation
@testable import ProjectZD8

/// テスト用の手動時計です。`sleep` は待たずに時刻を進めます。
final class DriveFlowManualClock: AcquisitionClock, @unchecked Sendable {
    private let lock = NSLock()
    private var now: Int64 = 0
    private var recordedSleeps: [Int64] = []

    func nowMicroseconds() -> Int64 { lock.withLock { now } }

    func sleep(microseconds: Int64) async {
        lock.withLock {
            recordedSleeps.append(microseconds)
            now += microseconds
        }
        await Task.yield()
    }

    /// 責務: 時刻を進めます。
    func advance(microseconds: Int64) { lock.withLock { now += microseconds } }

    /// 呼ばれた `sleep` の引数です。
    var sleeps: [Int64] { lock.withLock { recordedSleeps } }
}

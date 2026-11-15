import Foundation
@testable import ProjectZD8

/// テストが任意に進められる手動の単調時計です。
///
/// 実時間とは無関係に、`advance(byNanoseconds:)` で明示的に進めた分だけ現在値が増えます。
final class ManualMonotonicClock: MonotonicClockPort, @unchecked Sendable {
    /// 現在値を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した現在のナノ秒です。
    private var currentNanoseconds: UInt64

    /// 初期値を指定して手動時計を生成します。
    ///
    /// 責務: 指定した起点ナノ秒から始まる手動時計を構築します。
    /// - Parameter initialNanoseconds: 最初に返すナノ秒。既定は0。
    init(initialNanoseconds: UInt64 = 0) {
        currentNanoseconds = initialNanoseconds
    }

    /// 現在値をナノ秒で返します。
    ///
    /// 責務: ロック下で手動時計の現在値を1回読み取ります。
    /// - Returns: 初期値に加算済みの合計ナノ秒。
    func nowNanoseconds() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return currentNanoseconds
    }

    /// 時計を指定ナノ秒だけ進めます。
    ///
    /// 責務: ロック下で現在値へ加算します。
    /// - Parameter nanoseconds: 加算するナノ秒。
    func advance(byNanoseconds nanoseconds: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        currentNanoseconds += nanoseconds
    }
}

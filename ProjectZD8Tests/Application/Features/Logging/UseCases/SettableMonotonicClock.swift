import Foundation
@testable import ProjectZD8

/// テストが進めることも戻すこともできる手動の単調時計です。
///
/// 単調時計の読取が前回値を下回る異常を再現するために、`set(nanoseconds:)` で任意の値へ設定できます。
final class SettableMonotonicClock: MonotonicClockPort, @unchecked Sendable {
    /// 現在値を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した現在のナノ秒です。
    private var current: UInt64

    /// 初期値を指定して生成します。
    ///
    /// 責務: 指定したナノ秒から始まる手動時計を構築します。
    /// - Parameter initialNanoseconds: 最初に返すナノ秒。
    init(initialNanoseconds: UInt64 = 0) {
        current = initialNanoseconds
    }

    /// 現在値をナノ秒で返します。
    ///
    /// 責務: ロック下で現在値を1回読み取ります。
    /// - Returns: 現在のナノ秒。
    func nowNanoseconds() -> UInt64 {
        lock.withLock { current }
    }

    /// 時計を指定ナノ秒だけ進めます。
    ///
    /// 責務: 現在値へ指定量を加算します。
    /// - Parameter nanoseconds: 進めるナノ秒。
    func advance(byNanoseconds nanoseconds: UInt64) {
        lock.withLock { current += nanoseconds }
    }

    /// 時計を任意の値へ設定します。
    ///
    /// 責務: 現在値を置き換えます。前回より小さい値も設定できます。
    /// - Parameter nanoseconds: 設定するナノ秒。
    func set(nanoseconds: UInt64) {
        lock.withLock { current = nanoseconds }
    }
}

import Foundation

/// 端末スリープ中も進む `CLOCK_MONOTONIC` を読む本番の単調時計です。
///
/// Darwin の `CLOCK_MONOTONIC` は `ContinuousClock` と同じくスリープ中も進みます。
/// スリープ中に止まる `CLOCK_MONOTONIC_RAW`、`CLOCK_UPTIME_RAW`、`DispatchTime.uptimeNanoseconds` は使いません。
nonisolated struct ContinuousMonotonicClock: MonotonicClockPort {
    /// 状態を持たない単調時計を生成します。
    ///
    /// 責務: システム単調時計を読む境界を構築します。
    init() {}

    /// システム単調時計の現在値をナノ秒で返します。
    ///
    /// 責務: スリープ中の経過を含む `CLOCK_MONOTONIC` を1回読み取ります。
    /// - Returns: 端末起動からスリープ中を含めて経過したナノ秒。
    func nowNanoseconds() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_MONOTONIC)
    }
}

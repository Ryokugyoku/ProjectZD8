import Foundation

/// 単調時計(端末スリープ中も進み、実時刻の変更に影響されない)と `ContinuousClock` の待機で、常駐リンク監視の時刻と待機を提供します。
///
/// `now` は、生成時の実時刻を起点に単調時計の経過を足した時刻です。窓(10分)や見張りの上限(8時間)を、
/// 実時刻の変更やスリープに影響されずに計るためのもので、生成後に実時刻が変わっても追従しません。
/// 待機は `Task.sleep(for:)`(既定の `ContinuousClock`。スリープ中も進む)を使います。
@MainActor
final class SystemAdapterLinkSupervisionClock: AdapterLinkSupervisionClock {
    /// 経過を測る単調時計です。
    private let monotonic: any MonotonicClockPort
    /// 起点の単調時計の値です。
    private let originNanoseconds: UInt64
    /// 起点の実時刻です。
    private let originDate: Date

    /// 単調時計を注入して生成します。
    ///
    /// 責務: 単調時計の現在値と実時刻を起点として1回だけ読み取ります。
    /// - Parameter monotonic: スリープ中も進む単調時計。既定は `ContinuousMonotonicClock`。
    init(monotonic: any MonotonicClockPort = ContinuousMonotonicClock()) {
        self.monotonic = monotonic
        originNanoseconds = monotonic.nowNanoseconds()
        originDate = Date()
    }

    /// 起点の実時刻に単調時計の経過を足した現在時刻です。
    ///
    /// 責務: 単調時計の経過(スリープ中を含む)だけで進む時刻を返します。
    var now: Date {
        let current = monotonic.nowNanoseconds()
        let elapsed = current >= originNanoseconds ? current - originNanoseconds : 0
        return originDate.addingTimeInterval(TimeInterval(elapsed) / 1_000_000_000)
    }

    /// 指定した時間だけ待機します。
    ///
    /// 責務: スリープ中も進む `ContinuousClock` で待ち、呼び出し元タスクのキャンセルに従って待機を終えます。
    /// - Parameter duration: 待機する時間。
    /// - Throws: 待機中にキャンセルされた場合の `CancellationError`。
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration, clock: .continuous)
    }
}

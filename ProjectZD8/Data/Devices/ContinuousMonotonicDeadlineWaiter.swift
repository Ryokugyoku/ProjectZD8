/// 本番の単調時計(`ContinuousMonotonicClock`)の期限まで待つ境界です。
///
/// スリープ中も進む `ContinuousClock` で待ちます。待ちが早く/遅く返っても、呼び出し側が単調時計で判定し直します。
nonisolated struct ContinuousMonotonicDeadlineWaiter: LiveTelemetryDeadlineWaitPort {
    /// 残り時間の計算に使う単調時計です。
    private let clock: any MonotonicClockPort

    /// 残り時間の計算に使う単調時計を固定します。
    ///
    /// 責務: 期限と同じ基準の単調時計を注入します。
    /// - Parameter clock: 期限と同じ基準の単調時計。
    init(clock: any MonotonicClockPort = ContinuousMonotonicClock()) {
        self.clock = clock
    }

    /// 単調時計が指定値に達するまで待ちます。
    ///
    /// 責務: 現在値から期限までの残りを `ContinuousClock` で待ちます。既に過ぎていれば即座に返ります。
    /// - Parameter deadlineNanoseconds: 待ち終える単調時計の値。
    /// - Throws: 取消された場合は `CancellationError`。
    func wait(untilNanoseconds deadlineNanoseconds: UInt64) async throws {
        let now = clock.nowNanoseconds()
        guard deadlineNanoseconds > now else { return }
        let remaining = deadlineNanoseconds - now
        let clamped = Int64(clamping: remaining)
        try await Task.sleep(for: .nanoseconds(clamped), clock: .continuous)
    }
}

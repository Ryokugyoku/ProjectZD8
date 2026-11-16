/// 一時停止中の猶予(最後の受信から)と、一時停止を始めた時点から数える定期試行の予定をまとめます。
///
/// 猶予の判定と期限は `LiveTelemetryReceiveGrace` に任せ、この型は定期試行の時刻だけを管理します。
nonisolated struct LiveTelemetryPauseWindow: Equatable, Sendable {
    /// 一時停止を始めた時点の単調時計の値です。定期試行の起点にだけ使います。
    let pausedAtNanoseconds: UInt64
    /// 最後の受信からの猶予です。
    private(set) var grace: LiveTelemetryReceiveGrace
    /// 次に定期的な復帰の試行を行ってよい単調時計の値です。
    private(set) var nextRetryNanoseconds: UInt64

    /// 一時停止の開始時点と猶予を固定し、最初の定期試行を開始から1間隔後に予定します。
    ///
    /// 責務: 定期試行の起点を一時停止の開始時点へ、猶予の判定を最後の受信からの猶予へ固定します。
    /// - Parameters:
    ///   - pausedAtNanoseconds: 一時停止を始めた時点の単調時計の値。
    ///   - grace: 最後の受信からの猶予。
    init(pausedAtNanoseconds: UInt64, grace: LiveTelemetryReceiveGrace) {
        self.pausedAtNanoseconds = pausedAtNanoseconds
        self.grace = grace
        nextRetryNanoseconds = Self.adding(AcquisitionGracePeriodPolicy.retryIntervalNanoseconds, to: pausedAtNanoseconds)
    }

    /// 現在の時点で猶予を続けるか終えるかを返します。
    ///
    /// 責務: 最後の受信からの猶予の判定を返します。
    /// - Parameter nowNanoseconds: 単調時計の現在値。
    /// - Returns: 最後の受信から猶予内(ちょうど3分を含む)なら `.continueWaiting`、超えたら `.terminate`。
    func decision(nowNanoseconds: UInt64) -> AcquisitionGracePeriodDecision {
        grace.decision(nowNanoseconds: nowNanoseconds)
    }

    /// 猶予切れと判定される最初の単調時計の値を返します。
    ///
    /// 責務: 期限待ちに渡す値として、最後の受信からの猶予の期限を返します。
    var deadlineNanoseconds: UInt64 {
        grace.deadlineNanoseconds
    }

    /// アダプターは応答するのに車両が無応答だと分かったことを猶予へ反映します。
    ///
    /// 責務: 猶予と期限を「エンジン停止とみなす時間」へ縮めます。期限待ちは呼び出し側が張り直します。
    mutating func suspectVehicleOff() {
        grace.suspectVehicleOff()
    }

    /// 現在の時点で定期的な復帰の試行を行ってよいかを返します。
    ///
    /// 責務: 単調時計の現在値が次の試行時刻に達したかを判定します。時計が進まなければ何度呼んでも `false` です。
    /// - Parameter nowNanoseconds: 単調時計の現在値。
    /// - Returns: 次の試行時刻以上なら `true`。
    func isRetryDue(nowNanoseconds: UInt64) -> Bool {
        nowNanoseconds >= nextRetryNanoseconds
    }

    /// 復帰の試行を終えた時点から1間隔後に次の定期試行を予定します。
    ///
    /// 責務: 試行の成否や契機(定期・通知)にかかわらず、次の試行まで必ず1間隔を空けます。
    /// - Parameter attemptEndedNanoseconds: 試行を終えた時点の単調時計の値。
    mutating func scheduleNextRetry(afterAttemptEndedAt attemptEndedNanoseconds: UInt64) {
        let base = max(attemptEndedNanoseconds, pausedAtNanoseconds)
        nextRetryNanoseconds = Self.adding(AcquisitionGracePeriodPolicy.retryIntervalNanoseconds, to: base)
    }

    /// 単調時計の値へ経過を足します。
    ///
    /// 責務: 上限を超える場合は最大値へ丸めて加算します。
    /// - Parameters:
    ///   - interval: 足す経過ナノ秒。
    ///   - value: 起点の単調時計の値。
    /// - Returns: 加算した値、または `UInt64.max`。
    private static func adding(_ interval: UInt64, to value: UInt64) -> UInt64 {
        let (sum, overflow) = value.addingReportingOverflow(interval)
        return overflow ? .max : sum
    }
}

/// 一時停止を始めた時点から、猶予内かどうかと猶予切れの期限を求めます。
nonisolated struct LiveTelemetryPauseWindow: Equatable, Sendable {
    /// 一時停止を始めた時点の単調時計の値です。
    let pausedAtNanoseconds: UInt64

    /// 一時停止の開始時点を固定します。
    ///
    /// 責務: 猶予判定の起点を一時停止の開始時点へ固定します。
    /// - Parameters:
    /// - Parameter pausedAtNanoseconds: 一時停止を始めた時点の単調時計の値。
    init(pausedAtNanoseconds: UInt64) {
        self.pausedAtNanoseconds = pausedAtNanoseconds
    }

    /// 現在の時点で猶予を続けるか終えるかを返します。
    ///
    /// 責務: 単調時計の経過を猶予方針へ渡します。現在値が開始より小さい場合は経過0とします。
    /// - Parameter nowNanoseconds: 単調時計の現在値。
    /// - Returns: 猶予内(ちょうど3分を含む)なら `.continueWaiting`、超えたら `.terminate`。
    func decision(nowNanoseconds: UInt64) -> AcquisitionGracePeriodDecision {
        let elapsed = nowNanoseconds >= pausedAtNanoseconds ? nowNanoseconds - pausedAtNanoseconds : 0
        return AcquisitionGracePeriodPolicy().decision(elapsedSincePauseNanoseconds: elapsed)
    }

    /// 猶予切れと判定される最初の単調時計の値を返します。
    ///
    /// 責務: 期限待ちに渡す値として、猶予ちょうどの1ナノ秒後を求めます。上限を超える場合は最大値へ丸めます。
    var deadlineNanoseconds: UInt64 {
        let (sum, overflow) = pausedAtNanoseconds.addingReportingOverflow(AcquisitionGracePeriodPolicy.gracePeriodNanoseconds + 1)
        return overflow ? .max : sum
    }
}

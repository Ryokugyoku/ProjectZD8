/// 最後に正応答を受信した時点を起点に、猶予内かどうかと猶予切れの期限を求めます。
///
/// 同一プロセス内の猶予の判定はすべてこの型で行います(回復段階の各試行の前と成功の確定時、一時停止中の起床と成功の確定時)。
/// 起点は `LiveTelemetryReceiveTracker.lastReceivedNanoseconds` の値で、一時停止に入った時点ではありません。
/// 境界は `AcquisitionGracePeriodPolicy` に従い、経過がちょうど猶予までは続行、超えたら猶予切れです。
nonisolated struct LiveTelemetryReceiveGrace: Equatable, Sendable {
    /// 最後に正応答を受信した(正応答がまだ無ければ区間を開始した)時点の単調時計の値です。
    let lastReceivedNanoseconds: UInt64

    /// 猶予の起点を固定します。
    ///
    /// 責務: 最後の受信の単調時計の値を猶予の起点として保持します。
    /// - Parameter lastReceivedNanoseconds: 最後に正応答を受信した(または区間を開始した)時点の単調時計の値。
    init(lastReceivedNanoseconds: UInt64) {
        self.lastReceivedNanoseconds = lastReceivedNanoseconds
    }

    /// 現在の時点で猶予を続けるか終えるかを返します。
    ///
    /// 責務: 最後の受信からの単調時計の経過を猶予方針へ渡します。現在値が起点より小さい場合は経過0とします。
    /// - Parameter nowNanoseconds: 単調時計の現在値。
    /// - Returns: 猶予内(ちょうど3分を含む)なら `.continueWaiting`、超えたら `.terminate`。
    func decision(nowNanoseconds: UInt64) -> AcquisitionGracePeriodDecision {
        let elapsed = nowNanoseconds >= lastReceivedNanoseconds ? nowNanoseconds - lastReceivedNanoseconds : 0
        return AcquisitionGracePeriodPolicy().decision(elapsedSinceLastReceiveNanoseconds: elapsed)
    }

    /// 現在の時点で猶予が切れているかを返します。
    ///
    /// 責務: `decision(nowNanoseconds:)` が終了を選ぶかどうかを真偽値で返します。
    /// - Parameter nowNanoseconds: 単調時計の現在値。
    /// - Returns: 最後の受信から猶予を超えていれば `true`。
    func isExpired(nowNanoseconds: UInt64) -> Bool {
        decision(nowNanoseconds: nowNanoseconds) == .terminate
    }

    /// 猶予切れと判定される最初の単調時計の値を返します。
    ///
    /// 責務: 期限待ちに渡す値として、最後の受信から猶予ちょうどの1ナノ秒後を求めます。上限を超える場合は最大値へ丸めます。
    var deadlineNanoseconds: UInt64 {
        let (sum, overflow) = lastReceivedNanoseconds.addingReportingOverflow(AcquisitionGracePeriodPolicy.gracePeriodNanoseconds + 1)
        return overflow ? .max : sum
    }
}

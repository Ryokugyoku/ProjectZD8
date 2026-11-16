/// 取得が途切れた後、セッションを保ったまま回復を待つ猶予を、最後に正応答を受信した時点からの経過で判定します。
nonisolated struct AcquisitionGracePeriodPolicy: Sendable {
    /// 最後に正応答を受信した時点から回復を待つ猶予のナノ秒です(3分)。
    static let gracePeriodNanoseconds: UInt64 = 3 * 60 * 1_000_000_000
    /// 猶予中に、外部からの通知が無くても復帰を試す間隔のナノ秒です(10秒)。
    ///
    /// 直前の試行が終わった時点から数えます。回復操作がすぐ失敗する場合も、次の試行まで必ずこの間隔を空けます。
    static let retryIntervalNanoseconds: UInt64 = 10 * 1_000_000_000

    /// 状態を持たない猶予判定を生成します。
    ///
    /// 責務: 3分の固定猶予だけで判定するPolicyを構築します。
    init() {}

    /// 最後に正応答を受信した時点からの経過で猶予を続けるか終えるかを返します。
    ///
    /// 責務: 経過ナノ秒を猶予と比較し、ちょうど3分は続行、3分超過は終了とします。
    /// - Parameter elapsedSinceLastReceiveNanoseconds: 最後に正応答を受信してからの経過ナノ秒。
    /// - Returns: 経過が `gracePeriodNanoseconds` 以下なら `.continueWaiting`、超えたら `.terminate`。
    func decision(elapsedSinceLastReceiveNanoseconds: UInt64) -> AcquisitionGracePeriodDecision {
        elapsedSinceLastReceiveNanoseconds <= Self.gracePeriodNanoseconds ? .continueWaiting : .terminate
    }
}

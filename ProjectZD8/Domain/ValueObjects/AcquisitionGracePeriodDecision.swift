/// 取得の一時停止中に、猶予を続けるか終えるかの判断です。
nonisolated enum AcquisitionGracePeriodDecision: Equatable, Sendable {
    /// 猶予内のため、セッションを保ったまま回復を待ち続けます。
    case continueWaiting
    /// 猶予を超えたため、接続セッションを終了します。
    case terminate
}

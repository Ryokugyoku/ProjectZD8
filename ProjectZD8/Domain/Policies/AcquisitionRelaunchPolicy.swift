import Foundation

/// プロセス復帰時に、未終了セッションを同じセッションとして続けられるかを実時間で判定します。
///
/// 単調時計は端末の再起動をまたいで比較できないため、プロセスをまたぐ経過は実時間で測ります。
/// 実時間が最後にcommitした時刻より前を指す場合(時計の巻き戻り)は経過を信頼できないため終了とします。
nonisolated struct AcquisitionRelaunchPolicy: Sendable {
    /// 状態を持たない判定を生成します。
    ///
    /// 責務: 猶予方針と同じ3分で判定するPolicyを構築します。
    init() {}

    /// 最後にcommitした時刻から現在までの実時間の経過で、続行か終了かを返します。
    ///
    /// 責務: 実時間の経過を `AcquisitionGracePeriodPolicy` へ渡し、負の経過は終了とします。
    /// - Parameters:
    ///   - lastCommittedAt: 最後にcommitしたRawの観測時刻(Rawが無ければセッション開始時刻)。
    ///   - now: 判定する時点の実時間。
    /// - Returns: 経過が猶予以下(ちょうど3分を含む)なら `.continueWaiting`、超えたか負なら `.terminate`。
    func decision(lastCommittedAt: Date, now: Date) -> AcquisitionGracePeriodDecision {
        let elapsed = now.timeIntervalSince(lastCommittedAt)
        guard elapsed >= 0 else { return .terminate }
        let limitSeconds = Double(AcquisitionGracePeriodPolicy.gracePeriodNanoseconds) / 1_000_000_000
        guard elapsed <= limitSeconds else { return .terminate }
        let nanoseconds = UInt64((elapsed * 1_000_000_000).rounded(.down))
        return AcquisitionGracePeriodPolicy().decision(elapsedSincePauseNanoseconds: nanoseconds)
    }
}

import Foundation

/// 車両確認の窓(10分)と回数の安全上限から、次の確認を続けるかを決める純粋な方針です。
///
/// 窓の内か外かは確認の結果を受け取るたびに判定します(時刻は単調時計基準)。窓の終了時刻ちょうどは窓の外です。
/// アプリが前面にいる間は休止に入らず、窓切れでも回数の上限(窓 ÷ 最短間隔)到達でも、窓と回数を取り直して確認を続けます
/// (ユーザーが画面を見ている間は検知を止めないため)。背面では、窓切れまたは回数の上限で窓後の間隔(60秒)の確認へ移ります
/// (時計が進まない不具合でも、確認が空回りしないため)。
nonisolated struct AdapterLinkVehicleConfirmationWindowPolicy: Sendable {
    /// 確認窓と回数上限の定数です。
    let timing: AdapterLinkSupervisionTiming

    /// 時間定数を固定して生成します。
    ///
    /// 責務: 窓の長さと回数の上限を判定へ結び付けます。
    /// - Parameter timing: 確認窓と最短間隔。
    init(timing: AdapterLinkSupervisionTiming) {
        self.timing = timing
    }

    /// 次の確認を窓の内で続けるか・窓を取り直すか・窓後の間隔で続けるかを返します。
    ///
    /// 責務: 前面なら、回数の上限か窓切れで取り直し、どちらでもなければ続けます。背面なら、回数の上限か窓切れで窓後の間隔の確認へ移します。
    /// - Parameters:
    ///   - confirmation: 現在の確認進行状況。
    ///   - now: 結果を受け取った時刻。
    ///   - isForeground: アプリが前面にいるか。
    /// - Returns: 判定結果。
    func decision(
        for confirmation: AdapterLinkVehicleConfirmation,
        now: Date,
        isForeground: Bool
    ) -> AdapterLinkVehicleConfirmationWindowDecision {
        let isWithinAttemptLimit = confirmation.attemptCount < timing.maximumVehicleConfirmationAttempts
        if isWithinAttemptLimit, isInsideWindow(confirmation, now: now) { return .continueInWindow }
        return isForeground ? .renewWindow : .extendedConfirmation
    }

    /// 時刻が確認窓の内かどうかを返します。
    ///
    /// 責務: 窓の終了時刻より前(ちょうどは外)であることを判定します。
    /// - Parameters:
    ///   - confirmation: 現在の確認進行状況。
    ///   - now: 判定する時刻。
    /// - Returns: 窓の内なら `true`。
    func isInsideWindow(_ confirmation: AdapterLinkVehicleConfirmation, now: Date) -> Bool {
        now < confirmation.windowEndsAt
    }

    /// 指定した時刻から始まる新しい窓の確認進行状況を返します。
    ///
    /// 責務: アダプター判定結果を保ったまま、窓の終了時刻を `now` + 窓の長さに、回数を1に、段階を確認中にします。
    /// - Parameters:
    ///   - confirmation: 現在の確認進行状況。
    ///   - now: 新しい窓の起点。
    /// - Returns: 取り直した確認進行状況。
    func renewed(_ confirmation: AdapterLinkVehicleConfirmation, at now: Date) -> AdapterLinkVehicleConfirmation {
        AdapterLinkVehicleConfirmation(
            adapterProbeEvidence: confirmation.adapterProbeEvidence,
            windowEndsAt: now.addingTimeInterval(timing.vehicleConfirmationWindow),
            attemptCount: 1,
            phase: .probing
        )
    }
}

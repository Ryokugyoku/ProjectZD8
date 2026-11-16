import Foundation

/// 車両確認の窓(10分)と回数の安全上限から、次の確認を続けるかを決める純粋な方針です。
///
/// 窓の内か外かは確認の結果を受け取るたびに判定します(時刻は単調時計基準)。窓の終了時刻ちょうどは窓の外です。
/// アプリが前面にいる間は、窓切れを理由に休止せず窓を取り直します。回数の上限(窓 ÷ 最短間隔)は前面でも休止の理由になります
/// (時計が進まない不具合でも確認が無限に続かないため)。
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

    /// 次の確認を続けるか・窓を取り直すか・休止するかを返します。
    ///
    /// 責務: 回数の上限を先に判定し、次に窓の終了時刻と前面かどうかで判定します。
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
        guard confirmation.attemptCount < timing.maximumVehicleConfirmationAttempts else { return .pause }
        if isInsideWindow(confirmation, now: now) { return .continueInWindow }
        return isForeground ? .renewWindow : .pause
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

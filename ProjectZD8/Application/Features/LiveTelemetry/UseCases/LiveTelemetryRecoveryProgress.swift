/// 途絶からの回復で、現在の段階とその段階の失敗回数を進めます。
nonisolated struct LiveTelemetryRecoveryProgress: Equatable, Sendable {
    /// 次に試す回復段階です。
    private(set) var stage: AcquisitionRecoveryStage = .promptResync
    /// 現在の段階で失敗した試行回数です。
    private(set) var failedAttempts = 0

    /// 最初の段階(プロンプト再同期)から回復を始めます。
    ///
    /// 責務: 回復段階の進行を初期状態で構築します。
    init() {}

    /// 次に試す試行が現在の段階の何回目かを返します。
    ///
    /// 責務: 失敗回数から1始まりの試行番号を求めます。
    var attempt: Int { failedAttempts + 1 }

    /// 現在の段階の試行が失敗したことを反映し、次の動作を返します。
    ///
    /// 責務: 失敗回数を1増やして方針に次の動作を問い、次段階へ進む場合は段階と失敗回数を切り替えます。
    /// - Returns: 方針が選んだ次の動作。`enterGracePeriod` の場合は段階を変えません。
    mutating func recordFailure() -> AcquisitionRecoveryAction {
        failedAttempts += 1
        let action = AcquisitionStallPolicy().nextAction(after: stage, failedAttempts: failedAttempts)
        if case let .advance(next) = action {
            stage = next
            failedAttempts = 0
        }
        return action
    }
}

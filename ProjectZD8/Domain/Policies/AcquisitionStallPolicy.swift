/// 応答途絶の判定と、途絶からの回復段階の進め方を決定します。
nonisolated struct AcquisitionStallPolicy: Sendable {
    /// 最後の受信からこのナノ秒以上経過したら途絶とみなす閾値です(3秒)。
    static let stallThresholdNanoseconds: UInt64 = 3_000_000_000
    /// プロンプト再同期段階で失敗を許す試行回数の上限です。
    static let promptResyncAttemptLimit = 3
    /// `ATZ` からの再初期化段階で失敗を許す試行回数の上限です。
    static let reinitializeFromResetAttemptLimit = 2
    /// 切断して再接続する段階で失敗を許す試行回数の上限です。
    static let reconnectLinkAttemptLimit = 3

    /// 状態を持たない途絶判定を生成します。
    ///
    /// 責務: 定数だけで判定する途絶Policyを構築します。
    init() {}

    /// 最後の受信からの経過で応答途絶かを返します。
    ///
    /// 責務: 経過ナノ秒を途絶閾値と比較し、閾値ちょうども途絶とします。
    /// - Parameter elapsedSinceLastReceiveNanoseconds: 最後に受信してからの単調時計上の経過ナノ秒。
    /// - Returns: 経過が `stallThresholdNanoseconds` 以上なら `true`。
    func isStalled(elapsedSinceLastReceiveNanoseconds: UInt64) -> Bool {
        elapsedSinceLastReceiveNanoseconds >= Self.stallThresholdNanoseconds
    }

    /// 回復段階ごとの試行回数上限を返します。
    ///
    /// 責務: 1件の回復段階を対応する試行上限の定数へ変換します。
    /// - Parameter stage: 上限を調べる回復段階。
    /// - Returns: その段階で失敗を許す試行回数。
    func attemptLimit(for stage: AcquisitionRecoveryStage) -> Int {
        switch stage {
        case .promptResync: Self.promptResyncAttemptLimit
        case .reinitializeFromReset: Self.reinitializeFromResetAttemptLimit
        case .reconnectLink: Self.reconnectLinkAttemptLimit
        }
    }

    /// 現在段階で失敗した試行回数から次の動作を返します。
    ///
    /// 責務: 失敗回数が上限未満なら再試行、上限到達なら次段階、最終段階の上限到達なら猶予待ちを選びます。
    /// - Parameters:
    ///   - stage: 直前に試行した回復段階。
    ///   - failedAttempts: その段階で失敗した試行回数(直前の失敗を含む)。0以下は未失敗として再試行します。
    /// - Returns: 次に取る回復動作。
    func nextAction(after stage: AcquisitionRecoveryStage, failedAttempts: Int) -> AcquisitionRecoveryAction {
        guard failedAttempts >= attemptLimit(for: stage) else { return .retryCurrentStage }
        guard let next = nextStage(after: stage) else { return .enterGracePeriod }
        return .advance(to: next)
    }

    /// 回復段階の次の段階を返します。
    ///
    /// 責務: プロンプト再同期 → ATZ再初期化 → 再接続の順序を1段進めます。
    /// - Parameter stage: 現在の回復段階。
    /// - Returns: 次の回復段階。最終段階なら `nil`。
    private func nextStage(after stage: AcquisitionRecoveryStage) -> AcquisitionRecoveryStage? {
        switch stage {
        case .promptResync: .reinitializeFromReset
        case .reinitializeFromReset: .reconnectLink
        case .reconnectLink: nil
        }
    }
}

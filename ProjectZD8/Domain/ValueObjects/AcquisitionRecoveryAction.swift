/// 回復段階の試行が失敗した後に取る次の動作です。
nonisolated enum AcquisitionRecoveryAction: Equatable, Sendable {
    /// 同じ回復段階をもう一度試行します。
    case retryCurrentStage
    /// 指定した次の回復段階へ進みます。
    case advance(to: AcquisitionRecoveryStage)
    /// すべての回復段階を使い切ったため、取得を一時停止して猶予待ちへ移ります。
    case enterGracePeriod
}

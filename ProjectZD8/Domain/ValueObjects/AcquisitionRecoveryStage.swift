/// 応答途絶から取得を回復する段階です。
///
/// 軽い処置から順に `promptResync` → `reinitializeFromReset` → `reconnectLink` と進みます。
nonisolated enum AcquisitionRecoveryStage: String, Codable, Equatable, Sendable, CaseIterable {
    /// 空要求を送り直してアダプターのプロンプト `>` へ再同期します。
    case promptResync
    /// `ATZ` からアダプターの初期化手順をやり直します。
    case reinitializeFromReset
    /// 通信境界を切断して再接続します。
    case reconnectLink
}

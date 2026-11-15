/// 応答が途絶えたアダプターとの通信を段階的に立て直す能力です。
///
/// どの操作もトランスポートの応答待ちの上限(既存のタイムアウト)の中で終わります。成功はアダプターとの通信を
/// 立て直せたことだけを表し、車両が応答するかは呼び出し側が要求を送って確かめます。
protocol LiveTelemetryLinkRecoveryPort: Sendable {
    /// リンクを保ったまま、次のプロンプトまで読み捨てて応答の境界を合わせ直します。
    ///
    /// 責務: 開いているトランスポートへ空のコマンドを送り、プロンプト `>` までを読み捨てて新しい応答境界を作ります。
    /// - Parameter endpoint: 取得に使っているOBD終端。
    /// - Throws: 開いているトランスポートが無い・プロンプトが返らない場合は `LiveTelemetryLinkRecoveryError`、取消は `CancellationError`。
    func promptResync(using endpoint: OBDConnectionEndpoint) async throws

    /// リンクを保ったまま、`ATZ` からアダプターを初期化し直します。
    ///
    /// 責務: 既存のELM327初期化手順をリンクを切らずに実行し、送信ヘッダーの設定を初期状態へ戻します。
    /// - Parameter endpoint: 取得に使っているOBD終端。
    /// - Throws: 初期化を完了できない場合は `LiveTelemetryLinkRecoveryError`、取消は `CancellationError`。
    func reinitializeFromReset(using endpoint: OBDConnectionEndpoint) async throws

    /// リンクを切断して接続し直し、アダプターを初期化します。
    ///
    /// 責務: 保持中のトランスポートを閉じ、新しいトランスポートを開いて既存のELM327初期化手順を実行します。
    /// - Parameter endpoint: 取得に使っているOBD終端。
    /// - Throws: 接続または初期化を完了できない場合は `LiveTelemetryLinkRecoveryError`、取消は `CancellationError`。
    func reconnectLink(using endpoint: OBDConnectionEndpoint) async throws
}

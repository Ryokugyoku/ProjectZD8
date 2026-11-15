/// 取得が途切れて回復中または一時停止中であることを、表示用の判定と文言キーへ変換します。
///
/// iOSとmacOSで共通の判定です。セッションは続いているため「接続済み」とは表示せず、
/// 回復の段階または猶予待ちを表す文言キーを返します。
nonisolated struct LiveTelemetryPauseStatus: Equatable, Sendable {
    /// 取得ループが報告した段階です。`acquiring` 以外の値だけを持ちます。
    let acquisitionPhase: LiveTelemetryAcquisitionPhase

    /// 回復中または一時停止中の段階から表示状態を生成します。
    ///
    /// 責務: 取得中の段階を表示対象から除きます。
    /// - Parameter acquisitionPhase: 取得ループが報告した段階。
    /// - Returns: 回復中または一時停止中なら表示状態。取得中なら `nil`。
    init?(_ acquisitionPhase: LiveTelemetryAcquisitionPhase) {
        guard acquisitionPhase != .acquiring else { return nil }
        self.acquisitionPhase = acquisitionPhase
    }

    /// 回復操作を試している最中かどうかです。進捗表示の有無に使います。
    ///
    /// 責務: 回復中を `true`、猶予待ちを `false` へ変換します。
    var isRecovering: Bool {
        if case .recovering = acquisitionPhase { return true }
        return false
    }

    /// 状態を表すローカライズキーです。
    ///
    /// 責務: 回復段階または一時停止の原因を1件の文言キーへ変換します。
    var statusKey: String {
        switch acquisitionPhase {
        case .acquiring, .recovering(_, .promptResync, _):
            "telemetry.status.recovering.prompt_resync"
        case .recovering(_, .reinitializeFromReset, _):
            "telemetry.status.recovering.reinitialize"
        case .recovering(_, .reconnectLink, _):
            "telemetry.status.recovering.reconnect"
        case .paused(.responseStall):
            "telemetry.status.paused.no_response"
        case .paused(.linkLost):
            "telemetry.status.paused.link_lost"
        }
    }
}

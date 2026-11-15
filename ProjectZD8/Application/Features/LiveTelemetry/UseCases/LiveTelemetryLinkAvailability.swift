/// 取得ループが最後に受けたリンク可用性の通知から分かる、アダプターとのリンクの状態です。
///
/// 通知を一度も受けていなければ不明で、リンク復帰を明示的に受けた時だけ使えるとみなします。
/// 復帰の後に断を受けたら使えない状態へ戻ります。
nonisolated enum LiveTelemetryLinkAvailability: Equatable, Sendable {
    /// リンク可用性の通知をまだ受けていません。
    case unknown
    /// 最後に受けた通知がリンク復帰です。
    case available
    /// 最後に受けた通知がリンク断です。
    case unavailable

    /// 1件の通知を反映した後の状態を返します。
    ///
    /// 責務: リンク復帰は使える状態へ、リンク断は使えない状態へ変え、それ以外の通知(前面復帰・背面移行)では変えません。
    /// - Parameter signal: 取得ループの外から届いた通知。
    /// - Returns: 反映後の状態。
    func updated(by signal: LiveTelemetryAcquisitionWakeSignal) -> LiveTelemetryLinkAvailability {
        switch signal {
        case .linkRestored: .available
        case .linkLost: .unavailable
        case .foregroundEntered, .backgroundEntered: self
        }
    }
}

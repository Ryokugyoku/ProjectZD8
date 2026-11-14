/// 常駐リンクへの書き込みが完了しなかった理由を表します。
nonisolated enum AdapterLinkWriteError: Error, Equatable, Sendable {
    /// リンクが `ready` ではないため書き込みを受け付けませんでした。
    case notReady

    /// `stop()` により書き込み待ちが破棄されました。
    case stopped

    /// 書き込み完了前にリンクが `ready` から外れました。
    case linkLost

    /// OSが書き込み失敗を通知したか、最大書き込み長が不正でした。説明を保持します。
    case writeFailed(description: String)
}

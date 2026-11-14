/// 接続履歴一覧の各セッション行に出す保管操作の可否を判定します。
struct ConnectionHistorySessionActionPolicy {
    /// 1件のセッションへ手動iCloudアップロードを表示するかを返します。
    ///
    /// 責務: 終了済み、送信元Raw保持、未アップロードの条件と、自動アップロード無効または転送失敗を手動送信可否へ変換します。
    /// - Parameters:
    ///   - session: 判定対象の接続セッション。
    ///   - automaticUploadEnabled: セッション終了時の自動アップロードが有効か。
    /// - Returns: 一覧へアップロード操作を表示する場合は `true`。
    func canUpload(_ session: ConnectionSession, automaticUploadEnabled: Bool) -> Bool {
        guard session.endedAt != nil,
              session.rawLogSummary.localState != .removed,
              session.rawLogSummary.cloudState != .uploaded else { return false }
        return !automaticUploadEnabled || session.rawLogSummary.cloudState == .failed
    }

    /// 1件のセッションで安全な端末容量解放を選択できるかを返します。
    ///
    /// 責務: セッションの終了、ローカル保存、iCloud保管状態を容量解放可否へ変換します。
    /// - Parameter session: 判定対象の接続セッション。
    /// - Returns: iCloudに検証可能なManifestとともに保管済みのローカルRawがある場合は `true`。
    func canReleaseRawCache(_ session: ConnectionSession) -> Bool {
        session.endedAt != nil
            && session.rawLogSummary.localState == .available
            && session.rawLogSummary.recordCount > 0
            && session.rawLogSummary.cloudState == .uploaded
            && session.rawLogSummary.manifestDigest?.isEmpty == false
    }
}

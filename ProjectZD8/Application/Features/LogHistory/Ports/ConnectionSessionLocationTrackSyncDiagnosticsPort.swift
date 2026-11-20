/// 軌跡の即時アップロードの結果を診断へ残す口です。座標・セッションIDは渡しません。
nonisolated protocol ConnectionSessionLocationTrackSyncDiagnosticsPort: Sendable {
    /// 即時アップロードの失敗を記録します。
    ///
    /// 責務: エラーの domain と code だけを診断へ残します。
    func immediateUploadFailed(errorDomain: String, errorCode: Int)

    /// 即時アップロードの成功を記録します。
    ///
    /// 責務: アップロード件数だけを診断へ残します。
    func immediateUploadSucceeded(uploadedCount: Int)
}

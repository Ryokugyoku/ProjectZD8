/// 位置記録の保存失敗を握りつぶさず残す診断の境界です(DB が使えないと状態変化の行も書けないため)。
nonisolated protocol SessionLocationRecordingDiagnosticsPort: Sendable {
    /// 位置の保存失敗を残します。
    ///
    /// 責務: 1点の位置を保存できなかった事実を診断ログへ記録します。
    /// - Parameters:
    ///   - sessionID: 保存先の接続セッション。
    ///   - error: 保存の失敗。
    func sampleStorageFailed(sessionID: ConnectionSessionID, error: any Error)

    /// 状態変化の保存失敗を残します。
    ///
    /// 責務: 1件の状態変化を保存できなかった事実を診断ログへ記録します。
    /// - Parameters:
    ///   - kind: 保存できなかった状態の種類。
    ///   - sessionID: 保存先の接続セッション。
    ///   - error: 保存の失敗。
    func eventStorageFailed(
        _ kind: ConnectionSessionLocationEventKind,
        sessionID: ConnectionSessionID,
        error: any Error
    )
}

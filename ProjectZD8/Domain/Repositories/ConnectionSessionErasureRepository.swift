/// 接続セッション本体と子Rawログをセッション単位で物理削除します。
protocol ConnectionSessionErasureRepository {
    /// 指定アカウントが所有する1件の接続セッションを削除します。
    ///
    /// 責務: 1件のセッションIDに属する履歴本体と子Rawログを原子的に物理削除します。
    /// - Parameters:
    ///   - sessionID: 削除対象の接続セッションID。
    ///   - accountIdentifier: 削除対象を所有するAppleアカウント識別子。
    /// - Throws: 所有関係不一致、セッション不在、または永続化失敗。
    func deleteSession(
        _ sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) throws
}

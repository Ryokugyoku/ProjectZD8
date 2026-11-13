/// 接続セッションをアカウント単位で永続化し取得します。
protocol ConnectionSessionRepository {
    /// セッションの現在内容を新規保存または更新します。
    ///
    /// 責務: 1件の接続セッションを安定ID単位で永続化します。
    /// - Parameter session: 保存するセッションの現在内容。
    /// - Throws: 永続化を完了できない場合の保存先エラー。
    func save(_ session: ConnectionSession) throws

    /// 指定アカウントに属するセッションを新しい順で取得します。
    ///
    /// 責務: 1件のアカウント識別子に属する接続履歴を開始日時の降順で返します。
    /// - Parameter accountIdentifier: 取得対象のAppleアカウント識別子。
    /// - Returns: 開始日時が新しい順の接続セッション一覧。
    /// - Throws: 永続化済み履歴を取得できない場合の保存先エラー。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession]
}

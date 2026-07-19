/// 製品用セッションDBを準備できない場合に明示的失敗を返します。
struct UnavailableConnectionSessionRepository: ConnectionSessionRepository {
    /// 保存先利用不能を返します。
    ///
    /// 責務: セッション保存要求を利用不能エラーとして失敗させます。
    /// - Parameter session: 保存できない接続セッション。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func save(_ session: ConnectionSession) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 保存先利用不能を返します。
    ///
    /// 責務: セッション取得要求を利用不能エラーとして失敗させます。
    /// - Parameter accountIdentifier: 取得できないAppleアカウント識別子。
    /// - Returns: この実装は値を返しません。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession] {
        throw ConnectionSessionRepositoryError.unavailable
    }
}

/// 認証セッション識別子の安全な保存境界で発生する失敗です。
enum AuthenticationSessionStoreError: Error, Equatable {
    /// セッション識別子の読込、保存、削除を完了できませんでした。
    case unavailable
}

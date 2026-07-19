/// 認証済みアカウントに属するアプリ保存データの消去を抽象化します。
@MainActor
protocol AccountDataErasurePort: AnyObject {
    /// 指定アカウントの同期設定と端末設定を消去します。
    ///
    /// 責務: 1件のAppleユーザー識別子に対応するアプリ保存データを削除済み状態へします。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てた空でないユーザー識別子。
    func eraseAllData(for userIdentifier: String)
}

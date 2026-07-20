/// 認証済みアカウントに属するアプリ保存データの消去を抽象化します。
@MainActor
protocol AccountDataErasurePort: AnyObject {
    /// 指定アカウントの運転データ、同期設定、端末設定を消去します。
    ///
    /// 責務: 1件のAppleユーザー識別子に対応するアプリ保存データを削除済み状態へします。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てた空でないユーザー識別子。
    /// - Throws: ローカル運転データを完全に削除できない場合の保存先エラー。
    func eraseAllData(for userIdentifier: String) throws
}

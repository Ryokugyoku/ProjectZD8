/// 既定アダプターへの接続確認をシステム通知として提示する能力です。
@MainActor
protocol DefaultAdapterConnectionPrompting: AnyObject {
    /// 接続確認通知の操作受付と通知許可を準備します。
    ///
    /// 責務: 接続確認通知を提示できるシステム状態を準備します。
    /// - Parameter acceptance: ユーザーが接続開始を了承したときの通知先。
    /// - Returns: 通知提示が許可されている場合は `true`。
    /// - Side Effects: 初回はiOSの通知許可ダイアログを表示できます。
    func prepare(
        acceptance: @escaping @MainActor (OBDConnectionEndpoint) -> Void
    ) async -> Bool

    /// 接続可能になった既定アダプターの確認通知を提示します。
    ///
    /// 責務: 1件の既定アダプター終端をユーザー承認可能な通知へ変換します。
    /// - Parameter endpoint: 了承後に接続する物理終端。
    /// - Side Effects: iOSのローカル通知を配信します。
    func present(endpoint: OBDConnectionEndpoint)
}

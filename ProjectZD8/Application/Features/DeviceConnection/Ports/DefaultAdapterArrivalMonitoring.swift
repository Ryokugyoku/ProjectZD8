/// 保存済みBLEアダプターが接続可能になったことを監視する能力です。
@MainActor
protocol DefaultAdapterArrivalMonitoring: AnyObject {
    /// 指定された既定アダプターの到来監視を開始します。
    ///
    /// 責務: 1件の既定BLE識別情報を到来通知へ結び付けます。
    /// - Parameters:
    ///   - preference: 監視対象の既定アダプター設定。
    ///   - arrival: 対象アダプターを検出したときに通知する処理。
    /// - Side Effects: プラットフォームのBluetooth監視を開始します。
    func startMonitoring(
        preference: DefaultAdapterPreference,
        arrival: @escaping @MainActor (OBDConnectionEndpoint) -> Void
    )

    /// 現在の既定アダプター到来監視を終了します。
    ///
    /// 責務: 進行中の既定BLE監視を停止します。
    /// - Side Effects: プラットフォームのBluetooth監視を停止します。
    func stopMonitoring()
}

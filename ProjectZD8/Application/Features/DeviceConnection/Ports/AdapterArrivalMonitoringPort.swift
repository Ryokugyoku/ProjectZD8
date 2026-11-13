/// 既定アダプターが近くに現れたことを検知してユーザーへ知らせる契約です(iOSのBLEアダプターのみ)。
@MainActor
protocol AdapterArrivalMonitoringPort: AnyObject {
    /// 責務: 既定アダプターの出現監視を始めます。出現時に通知を出し、ユーザーが応じたら `onConnectRequested` を呼びます。
    func startMonitoring(_ adapter: AdapterDescriptor, onConnectRequested: @escaping @MainActor (AdapterDescriptor) -> Void)
    /// 責務: 出現監視を止めます。
    func stopMonitoring()
}

/// 記録中に端末がスリープしないようにする契約です。
@MainActor
protocol SleepInhibitingPort: AnyObject {
    /// 責務: スリープ抑止の有効・無効を切り替えます。
    func setInhibited(_ isInhibited: Bool)
}

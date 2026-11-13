/// 取得エンジンの出来事を他の機能へ配信する契約です。
@MainActor
protocol AcquisitionEventPublishing: AnyObject {
    /// 責務: 1件の取得の出来事を購読者へ配信します。
    func publish(_ event: AcquisitionEvent)
}

/// 設定画面から通知する「エンジン停止とみなす時間」の操作です。
enum VehicleOffDetectionDelayAction: Equatable, Sendable {
    /// 選択肢が選ばれたことを通知します。
    case delaySelected(VehicleOffDetectionDelay)
}

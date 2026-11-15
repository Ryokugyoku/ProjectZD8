/// 記録の調停役が、記録開始を断った理由と車両照合の失敗を診断記録へ残すための狭い境界です。
///
/// 失敗の観測は調停役の状態(`lastStartDeclineReason`・`lastVehicleLookupError`)でも行えます。この境界はログ等への出力だけを担います。
@MainActor
protocol VehicleRecordingDiagnosticsPort: AnyObject {
    /// 記録開始要求を断ったことを記録します。
    ///
    /// 責務: 1件の開始拒否の理由を診断記録へ渡します。
    /// - Parameter reason: 断った理由。
    func recordingStartDeclined(_ reason: VehicleRecordingStartDeclineReason)

    /// 登録済み車両の照合に失敗したことを記録します。
    ///
    /// 責務: 1件の照合エラーを診断記録へ渡します。記録は車両なしで続きます。
    /// - Parameter error: 照合で発生したエラー。
    func vehicleLookupFailed(_ error: any Error)
}

/// アカウント削除時に登録車両別PID収集設定を消去します。
protocol AccountVehiclePIDCapabilityErasureRepository {
    /// 指定車両群のPID対応情報と収集選択を削除します。
    ///
    /// 責務: 登録車両ID群に属する車両別PID設定をローカル保存先から削除済み状態へします。
    /// - Parameter vehicleIDs: 削除対象アカウントに登録されていた車両ID群。
    /// - Throws: 車両別PID設定を完全に削除できない場合の保存先エラー。
    func deleteCapabilities(for vehicleIDs: [VehicleID]) throws
}

/// アカウント削除の再試行に備えて、削除開始時に控えた車両IDを成功するまで保持する境界です。
///
/// 1回目の試行で車両キャッシュを消すため、再試行時にキャッシュから車両IDを復元できません。
/// 控えを保持することで、車両別PID設定を取りこぼさず消せます。
@MainActor
protocol AccountDeletionVehicleIDStorePort: AnyObject {
    /// 指定アカウントについて控えた車両IDを返します。
    ///
    /// 責務: 前回までの削除試行で控えた登録車両IDを復元します。控えが無ければ空配列です。
    /// - Parameter accountIdentifier: 削除対象のAppleアカウント識別子。
    /// - Returns: 控えた車両ID群。
    func pendingVehicleIDs(for accountIdentifier: String) -> [VehicleID]

    /// 指定アカウントの車両IDを控えとして保存します。
    ///
    /// 責務: 削除成功まで残る控えを、既存の控えと置き換えて保存します。
    /// - Parameters:
    ///   - vehicleIDs: 控える車両ID群。
    ///   - accountIdentifier: 削除対象のAppleアカウント識別子。
    func savePendingVehicleIDs(_ vehicleIDs: [VehicleID], for accountIdentifier: String)

    /// 指定アカウントの控えを消します。
    ///
    /// 責務: アカウント削除の成功後に、不要になった控えを削除済み状態へします。
    /// - Parameter accountIdentifier: 削除が成功したAppleアカウント識別子。
    func clearPendingVehicleIDs(for accountIdentifier: String)
}

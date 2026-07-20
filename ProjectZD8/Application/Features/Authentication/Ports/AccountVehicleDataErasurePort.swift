/// アカウントに属するCloudKit車両カタログと端末キャッシュを消去します。
@MainActor
protocol AccountVehicleDataErasurePort: AnyObject {
    /// CloudKitの車両カタログを削除します。
    ///
    /// 責務: 1件のアカウント識別子に属する車両カタログをCloudKitから削除済み状態へします。
    /// - Parameter accountIdentifier: 削除対象のAppleアカウント識別子。
    /// - Throws: CloudKit車両カタログを削除できない場合のエラー。
    func deleteAllVehicleData(for accountIdentifier: String) async throws

    /// 現在端末にキャッシュされた登録車両IDを返します。
    ///
    /// 責務: 1件のアカウント識別子に属するローカル車両キャッシュを車両ID群へ変換します。
    /// - Parameter accountIdentifier: 照会対象のAppleアカウント識別子。
    /// - Returns: キャッシュから復元できた登録車両ID群。
    func localVehicleIDs(for accountIdentifier: String) -> [VehicleID]

    /// 現在端末の車両カタログキャッシュだけを削除します。
    ///
    /// 責務: 遠隔失効した1件のアカウントに属する端末内車両キャッシュを削除済み状態へします。
    /// - Parameter accountIdentifier: 削除対象のAppleアカウント識別子。
    func removeLocalVehicleCache(for accountIdentifier: String)
}

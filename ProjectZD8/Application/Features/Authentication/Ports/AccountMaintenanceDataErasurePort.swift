/// アカウントに属するCloudKit上の整備カタログ(整備記録と整備写真)を消去します。
@MainActor
protocol AccountMaintenanceDataErasurePort: AnyObject {
    /// CloudKitの整備カタログを削除します。
    ///
    /// 責務: 1件のアカウント識別子に属する整備記録と整備写真をCloudKitから削除済み状態へします。
    /// - Parameter accountIdentifier: 削除対象のAppleアカウント識別子。
    /// - Throws: CloudKit整備カタログを削除できない場合のエラー。
    func deleteAllMaintenanceData(for accountIdentifier: String) async throws
}

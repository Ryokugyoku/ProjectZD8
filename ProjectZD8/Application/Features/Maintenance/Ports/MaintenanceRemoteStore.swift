/// CloudKitなどの端末間共有先へ整備記録集合を読み書きする能力です。
@MainActor
protocol MaintenanceRemoteStore {
    /// 指定アカウントの同期対象整備記録を取得します。
    ///
    /// 責務: 1件のアカウントスコープから墓石を含む遠隔整備集合を返します。
    /// - Parameter accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Returns: 遠隔保存されている整備記録集合。
    /// - Throws: 遠隔読込に失敗した場合のエラー。
    func fetchRecords(for accountIdentifier: String) async throws -> [MaintenanceRecord]

    /// 指定アカウントの同期対象整備記録を保存します。
    ///
    /// 責務: 1件のアカウントに対する整備記録集合を遠隔保存します。
    /// - Parameters:
    ///   - records: 墓石と写真を含む整備記録集合。
    ///   - accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Throws: 遠隔保存に失敗した場合のエラー。
    func saveRecords(_ records: [MaintenanceRecord], for accountIdentifier: String) async throws
}

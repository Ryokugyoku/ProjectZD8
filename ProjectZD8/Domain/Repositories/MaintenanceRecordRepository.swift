/// 端末内の車両別整備記録を読み書きする能力です。
protocol MaintenanceRecordRepository: Sendable {
    /// 指定アカウントに属する削除墓石を含む全整備記録を取得します。
    ///
    /// 責務: 1件のアカウントスコープから現在の整備記録集合を返します。
    /// - Parameter accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Returns: 更新日時の新しい順に並ぶ整備記録。
    /// - Throws: 永続化読込に失敗した場合のエラー。
    func records(for accountIdentifier: String) async throws -> [MaintenanceRecord]

    /// 指定アカウントへ整備記録を作成または更新します。
    ///
    /// 責務: 1件の整備記録を端末内の同一アカウントスコープへ保存します。
    /// - Parameters:
    ///   - record: 保存する整備記録。
    ///   - accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Throws: 永続化書込に失敗した場合のエラー。
    func save(_ record: MaintenanceRecord, for accountIdentifier: String) async throws

    /// 同期結果の記録集合で指定アカウントの端末内状態を置き換えます。
    ///
    /// 責務: 1件のアカウントに対する同期済み整備集合をトランザクション保存します。
    /// - Parameters:
    ///   - records: 墓石を含む同期済み記録集合。
    ///   - accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Throws: 一括保存に失敗した場合のエラー。
    func replaceAll(_ records: [MaintenanceRecord], for accountIdentifier: String) async throws
}

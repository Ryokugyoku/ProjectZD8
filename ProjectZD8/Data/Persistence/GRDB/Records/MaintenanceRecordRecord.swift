import Foundation
import GRDB

/// `maintenance_records` 行とDomain整備記録を相互変換します。
struct MaintenanceRecordRecord: Codable, FetchableRecord, PersistableRecord {
    /// 永続化先テーブル名です。
    static let databaseTableName = "maintenance_records"
    /// 整備記録ID文字列です。
    let id: String
    /// Appleアカウント識別子です。
    let accountIdentifier: String
    /// 登録車両ID文字列です。
    let vehicleID: String
    /// 軽整備または重整備の区分です。
    let kind: String
    /// 整備実施日時です。
    let performedAt: Date
    /// 最終更新日時です。
    let updatedAt: Date
    /// 削除墓石日時です。
    let deletedAt: Date?
    /// 写真を含む完全な整備記録JSONです。
    let payload: Data

    /// Domain整備記録を検索列付きSQLite行へ変換します。
    ///
    /// 責務: 1件の整備記録を索引列と復元可能なJSONへ符号化します。
    /// - Parameters:
    ///   - record: 永続化するDomain整備記録。
    ///   - accountIdentifier: 所有するAppleアカウント識別子。
    /// - Throws: JSON符号化に失敗した場合のエラー。
    init(record: MaintenanceRecord, accountIdentifier: String) throws {
        id = record.id.rawValue.uuidString.lowercased()
        self.accountIdentifier = accountIdentifier
        vehicleID = record.vehicleID.rawValue.uuidString.lowercased()
        kind = record.kind.rawValue
        performedAt = record.performedAt
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        payload = try JSONEncoder().encode(record)
    }

    /// SQLite行から完全なDomain整備記録を復元します。
    ///
    /// 責務: 1件の永続化JSONをDomain整備記録へ復号します。
    /// - Returns: 復元した車両別整備記録。
    /// - Throws: JSONが不正な場合の復号エラー。
    func makeDomainRecord() throws -> MaintenanceRecord {
        try JSONDecoder().decode(MaintenanceRecord.self, from: payload)
    }
}

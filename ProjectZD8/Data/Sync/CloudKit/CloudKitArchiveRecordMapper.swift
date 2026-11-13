import CloudKit
import Foundation

/// セッションのRawアーカイブのレコード(`RTSessionArchive`)を作り、読み取ります。コンテナ不要の純粋な変換です。
///
/// アーカイブゾーンに置き、レコード名はセッションのUUIDです。車両は参照ではなく文字列で持ちます
/// (ゾーンをまたぐ参照は作れないため、車両削除時の連鎖はアプリが行います)。
nonisolated struct CloudKitArchiveRecordMapper: Sendable {
    /// レコードタイプ名です。
    static let recordType = "RTSessionArchive"

    /// レコードのフィールド名です。
    nonisolated enum Field {
        static let archive = "archive"
        static let archiveDigest = "archiveDigest"
        static let vehicleID = "vehicleID"
    }

    /// 対象のゾーンです。
    let zoneID: CKRecordZone.ID

    /// 責務: 指定ゾーンのアーカイブレコードを扱う変換器を生成します。
    init(zoneID: CKRecordZone.ID = CloudKitSyncConfiguration.archiveZoneID) {
        self.zoneID = zoneID
    }

    /// 責務: セッションのアーカイブレコードのIDを返します。
    func recordID(sessionID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: sessionID, zoneID: zoneID)
    }

    /// 責務: アップロードする新しいアーカイブレコードを作ります。
    /// - Parameter fileURL: 圧縮済みアーカイブを書き出したファイル。
    func record(sessionID: String, vehicleID: String, digest: String, fileURL: URL) -> CKRecord {
        let record = CKRecord(recordType: Self.recordType, recordID: recordID(sessionID: sessionID))
        apply(to: record, vehicleID: vehicleID, digest: digest, fileURL: fileURL)
        return record
    }

    /// 責務: 既存のレコード(サーバーの版など)へアーカイブの内容を上書きします。
    func apply(to record: CKRecord, vehicleID: String, digest: String, fileURL: URL) {
        record[Field.archive] = CKAsset(fileURL: fileURL)
        record[Field.archiveDigest] = digest
        record[Field.vehicleID] = vehicleID
    }

    /// 責務: サーバーに既にあるレコードが同じ検証値のアーカイブかどうかを返します。
    static func isSameArchive(_ record: CKRecord, digest: String) -> Bool {
        record.recordType == recordType && (record[Field.archiveDigest] as? String)?.lowercased() == digest.lowercased()
    }
}

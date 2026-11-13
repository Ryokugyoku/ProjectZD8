import CloudKit
import Foundation

/// 同期レコードの内容と `CKRecord` を相互に変換します。コンテナが無くても動く純粋な変換です。
///
/// フィールド名はテーブルの列名と同じです。日時はエポックミリ秒の `Int64`、真偽値は `Int64` の0/1です。
/// 子レコードは `vehicle` フィールドに親車両への削除連鎖(`deleteSelf`)参照を持ちます。
/// セッションのRawアーカイブは載せず(`CloudKitArchiveRecordMapper` が別ゾーンへ置きます)、検証値だけを持ちます。
nonisolated struct CloudKitRecordMapper: Sendable {
    /// レコードのフィールド名です。
    nonisolated enum Field {
        static let vehicle = "vehicle"
        static let image = "image"
        static let archiveDigest = "archiveDigest"
    }

    /// 対象のゾーンです。
    let zoneID: CKRecordZone.ID

    /// 責務: 指定ゾーンのレコードを扱う変換器を生成します。
    init(zoneID: CKRecordZone.ID = CloudKitSyncConfiguration.zoneID) {
        self.zoneID = zoneID
    }

    // MARK: - ローカル → CloudKit

    /// 責務: 送信材料から保存用の `CKRecord` を作ります。
    ///
    /// システムフィールドがあればそれを土台にし、変更したフィールドだけが送信されるようにします。
    func record(for outgoing: SyncOutgoingRecord) -> CKRecord {
        let payload = outgoing.payload
        let record = baseRecord(type: payload.recordType, name: payload.recordName, systemFields: outgoing.systemFields)
        switch payload {
        case .vehicle(let row):
            record["vin"] = row.vin
            record["obdIdentifier"] = row.obdIdentifier
            record["name"] = row.name
            record["manufacturer"] = row.manufacturer
            record["engineModel"] = row.engineModel
            record["powertrain"] = row.powertrain
            record["energySources"] = row.energySources
            record["tankCapacityLiters"] = row.tankCapacityLiters
            record["modelYear"] = row.modelYear.map(Int64.init)
            record["note"] = row.note
            record["photoID"] = row.photoID
            record["createdAt"] = row.createdAt
            record["modifiedAt"] = row.modifiedAt
        case .maintenanceRecord(let row):
            record[Field.vehicle] = vehicleReference(row.vehicleID)
            record["kind"] = row.kind
            record["title"] = row.title
            record["performedAt"] = row.performedAt
            record["odometerKilometers"] = row.odometerKilometers
            record["notes"] = row.notes
            record["detail"] = row.detail
            record["createdAt"] = row.createdAt
            record["modifiedAt"] = row.modifiedAt
        case .photo(let row):
            record[Field.vehicle] = vehicleReference(row.vehicleID)
            record["byteCount"] = Int64(row.byteCount)
            record["createdAt"] = row.createdAt
            record["modifiedAt"] = row.modifiedAt
            if let url = outgoing.photoFileURL {
                record[Field.image] = CKAsset(fileURL: url)
            }
        case .driveSession(let row):
            record[Field.vehicle] = vehicleReference(row.vehicleID)
            record["startedAt"] = row.startedAt
            record["endedAt"] = row.endedAt
            record["endReason"] = row.endReason
            record["isDemo"] = Int64(row.isDemo ? 1 : 0)
            record["adapterName"] = row.adapterName
            record["adapterTransport"] = row.adapterTransport
            record["platform"] = row.platform
            record["deviceID"] = row.deviceID
            record["deviceName"] = row.deviceName
            record["appVersion"] = row.appVersion
            record["appBuild"] = row.appBuild
            record["pollingPolicyVersion"] = Int64(row.pollingPolicyVersion)
            record["odometerStartKilometers"] = row.odometerStartKilometers
            record["odometerEndKilometers"] = row.odometerEndKilometers
            record["distanceSource"] = row.distanceSource
            record["sampleCount"] = Int64(row.sampleCount)
            record["respondedCount"] = Int64(row.respondedCount)
            record["payloadByteCount"] = Int64(row.payloadByteCount)
            record["modifiedAt"] = row.modifiedAt
            record[Field.archiveDigest] = row.archiveDigest
        }
        return record
    }

    /// 責務: 削除や照会に使うレコードIDを返します。
    func recordID(name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    // MARK: - CloudKit → ローカル

    /// 責務: 取得した `CKRecord` を同期レコードの内容へ変換します。
    ///
    /// セッションの `rawAvailability` は仮に `cloudOnly` とし、適用時に既存行の値で置き換えます。
    /// - Throws: 未知のレコードタイプや必須フィールドの欠落は `SyncLocalStoreError.invalidValue`。
    func payload(from record: CKRecord) throws -> SyncRecordPayload {
        guard let type = SyncRecordType(rawValue: record.recordType) else { throw SyncLocalStoreError.invalidValue("recordType") }
        let id = record.recordID.recordName
        switch type {
        case .vehicle:
            return .vehicle(SyncVehicleRow(
                id: id,
                vin: try string(record, "vin"),
                obdIdentifier: record["obdIdentifier"] as? String,
                name: try string(record, "name"),
                manufacturer: try string(record, "manufacturer"),
                engineModel: try string(record, "engineModel"),
                powertrain: try string(record, "powertrain"),
                energySources: try string(record, "energySources"),
                tankCapacityLiters: record["tankCapacityLiters"] as? Double,
                modelYear: (record["modelYear"] as? Int64).map { Int($0) },
                note: try string(record, "note"),
                photoID: record["photoID"] as? String,
                createdAt: try int64(record, "createdAt"),
                modifiedAt: try int64(record, "modifiedAt"),
                deletedAt: nil
            ))
        case .maintenanceRecord:
            return .maintenanceRecord(SyncMaintenanceRow(
                id: id,
                vehicleID: try vehicleID(record),
                kind: try string(record, "kind"),
                title: try string(record, "title"),
                performedAt: try int64(record, "performedAt"),
                odometerKilometers: record["odometerKilometers"] as? Double,
                notes: try string(record, "notes"),
                detail: try data(record, "detail"),
                createdAt: try int64(record, "createdAt"),
                modifiedAt: try int64(record, "modifiedAt"),
                deletedAt: nil
            ))
        case .photo:
            return .photo(SyncPhotoRow(
                id: id,
                vehicleID: try vehicleID(record),
                byteCount: Int(try int64(record, "byteCount")),
                createdAt: try int64(record, "createdAt"),
                modifiedAt: try int64(record, "modifiedAt"),
                deletedAt: nil
            ))
        case .driveSession:
            return .driveSession(SyncSessionRow(
                id: id,
                vehicleID: try vehicleID(record),
                startedAt: try int64(record, "startedAt"),
                endedAt: try int64(record, "endedAt"),
                endReason: try string(record, "endReason"),
                isDemo: try int64(record, "isDemo") != 0,
                adapterName: try string(record, "adapterName"),
                adapterTransport: try string(record, "adapterTransport"),
                platform: try string(record, "platform"),
                deviceID: try string(record, "deviceID"),
                deviceName: try string(record, "deviceName"),
                appVersion: try string(record, "appVersion"),
                appBuild: try string(record, "appBuild"),
                pollingPolicyVersion: Int(try int64(record, "pollingPolicyVersion")),
                odometerStartKilometers: record["odometerStartKilometers"] as? Double,
                odometerEndKilometers: record["odometerEndKilometers"] as? Double,
                distanceSource: record["distanceSource"] as? String,
                sampleCount: Int(try int64(record, "sampleCount")),
                respondedCount: Int(try int64(record, "respondedCount")),
                payloadByteCount: Int(try int64(record, "payloadByteCount")),
                rawAvailability: RawAvailability.cloudOnly.rawValue,
                archiveDigest: record[Field.archiveDigest] as? String,
                modifiedAt: try int64(record, "modifiedAt"),
                deletedAt: nil
            ))
        }
    }

    // MARK: - システムフィールド

    /// 責務: レコードのシステムフィールド(変更タグなど)だけをバイト列にします。
    static func encodeSystemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    /// 責務: システムフィールドのバイト列からフィールドの無いレコードを復元します。壊れていれば `nil` です。
    static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }

    // MARK: - 内部

    /// 責務: システムフィールドを土台に、無ければ新規のレコードを作ります。
    private func baseRecord(type: SyncRecordType, name: String, systemFields: Data?) -> CKRecord {
        if let systemFields, let record = Self.decodeSystemFields(systemFields),
           record.recordType == type.rawValue, record.recordID.recordName == name {
            return record
        }
        return CKRecord(recordType: type.rawValue, recordID: recordID(name: name))
    }

    /// 責務: 親車両への削除連鎖参照を作ります。
    private func vehicleReference(_ vehicleID: String) -> CKRecord.Reference {
        CKRecord.Reference(recordID: recordID(name: vehicleID), action: .deleteSelf)
    }

    /// 責務: 親車両の参照からその車両IDを読みます。
    private func vehicleID(_ record: CKRecord) throws -> String {
        guard let reference = record[Field.vehicle] as? CKRecord.Reference else { throw SyncLocalStoreError.invalidValue(Field.vehicle) }
        return reference.recordID.recordName
    }

    /// 責務: 必須の文字列フィールドを読みます。
    private func string(_ record: CKRecord, _ key: String) throws -> String {
        guard let value = record[key] as? String else { throw SyncLocalStoreError.invalidValue(key) }
        return value
    }

    /// 責務: 必須の整数フィールドを読みます。
    private func int64(_ record: CKRecord, _ key: String) throws -> Int64 {
        guard let value = record[key] as? Int64 else { throw SyncLocalStoreError.invalidValue(key) }
        return value
    }

    /// 責務: 必須のバイト列フィールドを読みます。
    private func data(_ record: CKRecord, _ key: String) throws -> Data {
        guard let value = record[key] as? Data else { throw SyncLocalStoreError.invalidValue(key) }
        return value
    }
}

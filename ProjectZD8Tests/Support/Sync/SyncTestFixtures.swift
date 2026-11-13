import Foundation
import GRDB
@testable import ProjectZD8

/// 同期のテストで使う行と一時ディレクトリを作ります。
enum SyncTestFixtures {
    /// 責務: 新しい小文字UUID文字列を返します。
    static func newID() -> String {
        UUID().uuidString.lowercased()
    }

    /// 責務: 車両行を作ります。
    static func vehicle(id: String = newID(), name: String = "ZD8", modifiedAt: Int64 = 1_000, deletedAt: Int64? = nil, photoID: String? = nil) -> SyncVehicleRow {
        SyncVehicleRow(
            id: id, vin: "JF1ZD8", obdIdentifier: nil, name: name, manufacturer: "SUBARU", engineModel: "FA24",
            powertrain: "combustion", energySources: "[\"gasolinePremium\"]", tankCapacityLiters: 50, modelYear: 2022,
            note: "", photoID: photoID, createdAt: 500, modifiedAt: modifiedAt, deletedAt: deletedAt
        )
    }

    /// 責務: 整備記録行を作ります。
    static func maintenance(id: String = newID(), vehicleID: String, modifiedAt: Int64 = 1_000, deletedAt: Int64? = nil) -> SyncMaintenanceRow {
        SyncMaintenanceRow(
            id: id, vehicleID: vehicleID, kind: "light", title: "Oil", performedAt: 900, odometerKilometers: 12_345.5,
            notes: "n", detail: Data("{\"workItems\":[]}".utf8), createdAt: 800, modifiedAt: modifiedAt, deletedAt: deletedAt
        )
    }

    /// 責務: 写真行を作ります。
    static func photo(id: String = newID(), vehicleID: String, modifiedAt: Int64 = 1_000, deletedAt: Int64? = nil) -> SyncPhotoRow {
        SyncPhotoRow(id: id, vehicleID: vehicleID, byteCount: 4, createdAt: 700, modifiedAt: modifiedAt, deletedAt: deletedAt)
    }

    /// 責務: セッション行を作ります。既定は終了済み・デモ以外・Rawローカルです。
    static func session(
        id: String = newID(),
        vehicleID: String,
        ended: Bool = true,
        isDemo: Bool = false,
        rawAvailability: RawAvailability = .local,
        archiveDigest: String? = nil,
        sampleCount: Int = 0,
        modifiedAt: Int64 = 1_000,
        deletedAt: Int64? = nil
    ) -> SyncSessionRow {
        SyncSessionRow(
            id: id, vehicleID: vehicleID, startedAt: 100, endedAt: ended ? 200 : nil, endReason: ended ? "userStopped" : nil,
            isDemo: isDemo, adapterName: "vLinker", adapterTransport: "bluetoothLowEnergy", platform: "mac",
            deviceID: "device", deviceName: "Mac", appVersion: "1.0", appBuild: "1", pollingPolicyVersion: 1,
            odometerStartKilometers: 10, odometerEndKilometers: 20, distanceSource: "odometer",
            sampleCount: sampleCount, respondedCount: sampleCount, payloadByteCount: sampleCount * 2,
            rawAvailability: rawAvailability.rawValue, archiveDigest: archiveDigest, modifiedAt: modifiedAt, deletedAt: deletedAt
        )
    }

    /// 責務: セッションにPID1件とサンプル `count` 件を追加します。
    static func insertRaw(_ db: Database, sessionID: String, count: Int) throws {
        try SyncSessionPIDRow(
            sessionID: sessionID, ordinal: 0, service: 1, pid: 0x0C, header: nil, support: "supported",
            isCollectionEnabled: true, isFastGroup: true, definitionRevision: 1, requiredByteCount: 2,
            formula: "(A*256+B)/4", unit: "rpm", minimumValue: 0, maximumValue: 16_383
        ).insert(db)
        for index in 0..<count {
            try SyncSessionSampleRow(
                sessionID: sessionID, sequence: Int64(index), tick: index, elapsedMicroseconds: Int64(index) * 1_000,
                service: 1, pid: 0x0C, outcome: 0, payload: Data([0x0B, UInt8(index % 256)])
            ).insert(db)
        }
    }

    /// 責務: 同期済みとして `sync_records` 行を入れます。
    static func markSynced(_ db: Database, type: SyncRecordType, id: String, syncedModifiedAt: Int64, systemFields: Data? = Data([1])) throws {
        try SyncRecordMetadataRow(recordType: type.rawValue, recordID: id, systemFields: systemFields, syncedModifiedAt: syncedModifiedAt).save(db)
    }

    /// 責務: テストごとの一時ディレクトリにある写真ストアを返します。
    static func photoStore() -> PhotoFileStore {
        PhotoFileStore(directory: FileManager.default.temporaryDirectory.appending(path: "SyncTests-\(UUID().uuidString)", directoryHint: .isDirectory))
    }
}

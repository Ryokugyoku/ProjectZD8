import Foundation
import XCTest
@testable import ProjectZD8

/// 車両別整備記録の双方向統合規則を検証します。
@MainActor
final class SynchronizeMaintenanceRecordsUseCaseTests: XCTestCase {
    /// 同じ記録IDでは更新日時が新しい側を採用します。
    ///
    /// 責務: iPhoneとMacで同一記録を編集した場合に新しい変更だけが残ることを確認します。
    func testMergeUsesNewestVersionForSameRecord() {
        let id = MaintenanceRecordID()
        let vehicleID = VehicleID()
        let older = MaintenanceRecord(
            id: id,
            vehicleID: vehicleID,
            kind: .light,
            title: "Older",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = MaintenanceRecord(
            id: id,
            vehicleID: vehicleID,
            kind: .light,
            title: "Newer",
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let merged = SynchronizeMaintenanceRecordsUseCase.merge(local: [newer], remote: [older])

        XCTAssertEqual(merged.map(\.title), ["Newer"])
    }

    /// 新しい削除墓石が古い実体より優先されます。
    ///
    /// 責務: 一方の端末で削除した記録が他端末の古い内容から復活しないことを確認します。
    func testMergePreservesNewerDeletionTombstone() throws {
        let id = MaintenanceRecordID()
        let vehicleID = VehicleID()
        let active = MaintenanceRecord(
            id: id,
            vehicleID: vehicleID,
            kind: .heavy,
            title: "Engine overhaul",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let deletedAt = Date(timeIntervalSince1970: 300)
        var deleted = active
        deleted.updatedAt = deletedAt
        deleted.deletedAt = deletedAt

        let merged = SynchronizeMaintenanceRecordsUseCase.merge(local: [active], remote: [deleted])

        XCTAssertEqual(try XCTUnwrap(merged.first).deletedAt, deletedAt)
    }

    /// 異なる車両の記録をID単位で混在させず保持します。
    ///
    /// 責務: 複数車両の軽整備と重整備が双方向統合後も各車両IDへ紐づくことを確認します。
    func testMergeKeepsRecordsForEveryVehicle() {
        let firstVehicle = VehicleID()
        let secondVehicle = VehicleID()
        let light = MaintenanceRecord(vehicleID: firstVehicle, kind: .light, title: "Oil")
        let heavy = MaintenanceRecord(vehicleID: secondVehicle, kind: .heavy, title: "Gearbox")

        let merged = SynchronizeMaintenanceRecordsUseCase.merge(local: [light], remote: [heavy])

        XCTAssertEqual(Set(merged.map(\.vehicleID)), Set([firstVehicle, secondVehicle]))
    }

    /// 双方向統合結果をローカルと遠隔の両方へ同じ内容で保存します。
    ///
    /// 責務: 1回の同期がiPhone側記録とMac側記録を両保存先へ反映することを確認します。
    func testExecutePersistsMergedRecordsToBothStores() async throws {
        let localRecord = MaintenanceRecord(vehicleID: VehicleID(), kind: .light, title: "Oil")
        let remoteRecord = MaintenanceRecord(vehicleID: VehicleID(), kind: .heavy, title: "Engine")
        let local = MaintenanceRecordRepositoryFake(records: [localRecord])
        let remote = MaintenanceRemoteStoreFake(records: [remoteRecord])
        let useCase = SynchronizeMaintenanceRecordsUseCase(localRepository: local, remoteStore: remote)

        let visible = try await useCase.execute(accountIdentifier: "account")

        XCTAssertEqual(Set(visible.map(\.id)), Set([localRecord.id, remoteRecord.id]))
        XCTAssertEqual(Set(local.storedRecords.map(\.id)), Set([localRecord.id, remoteRecord.id]))
        XCTAssertEqual(Set(remote.storedRecords.map(\.id)), Set([localRecord.id, remoteRecord.id]))
    }
}

/// 同期テスト用の端末内整備保存先です。
@MainActor
private final class MaintenanceRecordRepositoryFake: MaintenanceRecordRepository {
    /// 現在保持する整備記録です。
    var storedRecords: [MaintenanceRecord]

    /// 初期の端末内記録を保持します。
    ///
    /// 責務: 同期テストのローカル初期集合を固定します。
    /// - Parameter records: 初期整備記録集合。
    init(records: [MaintenanceRecord]) {
        storedRecords = records
    }

    /// 固定した端末内記録を返します。
    ///
    /// 責務: 同期要求へ現在のローカル集合を返します。
    /// - Parameter accountIdentifier: テストで受け取るアカウント識別子。
    /// - Returns: 現在の端末内記録集合。
    func records(for accountIdentifier: String) async throws -> [MaintenanceRecord] { storedRecords }

    /// 1件の端末内記録をupsertします。
    ///
    /// 責務: 保存要求1件をテスト用ローカル集合へ反映します。
    /// - Parameters:
    ///   - record: 保存する整備記録。
    ///   - accountIdentifier: テストで受け取るアカウント識別子。
    func save(_ record: MaintenanceRecord, for accountIdentifier: String) async throws {
        storedRecords.removeAll { $0.id == record.id }
        storedRecords.append(record)
    }

    /// 同期済み集合で端末内記録を置き換えます。
    ///
    /// 責務: 同期結果をテスト用ローカル集合へそのまま保存します。
    /// - Parameters:
    ///   - records: 同期済み整備記録集合。
    ///   - accountIdentifier: テストで受け取るアカウント識別子。
    func replaceAll(_ records: [MaintenanceRecord], for accountIdentifier: String) async throws {
        storedRecords = records
    }
}

/// 同期テスト用の遠隔整備保存先です。
@MainActor
private final class MaintenanceRemoteStoreFake: MaintenanceRemoteStore {
    /// 現在保持する遠隔整備記録です。
    var storedRecords: [MaintenanceRecord]

    /// 初期の遠隔記録を保持します。
    ///
    /// 責務: 同期テストの遠隔初期集合を固定します。
    /// - Parameter records: 初期整備記録集合。
    init(records: [MaintenanceRecord]) {
        storedRecords = records
    }

    /// 固定した遠隔記録を返します。
    ///
    /// 責務: 同期要求へ現在の遠隔集合を返します。
    /// - Parameter accountIdentifier: テストで受け取るアカウント識別子。
    /// - Returns: 現在の遠隔記録集合。
    func fetchRecords(for accountIdentifier: String) async throws -> [MaintenanceRecord] { storedRecords }

    /// 同期済み集合で遠隔記録を置き換えます。
    ///
    /// 責務: 同期結果をテスト用遠隔集合へそのまま保存します。
    /// - Parameters:
    ///   - records: 同期済み整備記録集合。
    ///   - accountIdentifier: テストで受け取るアカウント識別子。
    func saveRecords(_ records: [MaintenanceRecord], for accountIdentifier: String) async throws {
        storedRecords = records
    }
}

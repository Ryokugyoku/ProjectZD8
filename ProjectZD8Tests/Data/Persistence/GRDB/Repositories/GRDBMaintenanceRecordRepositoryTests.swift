import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// GRDB整備記録Repositoryの写真と締結証跡を含む往復保存を検証します。
@MainActor
final class GRDBMaintenanceRecordRepositoryTests: XCTestCase {
    /// 重整備の写真、分解本数、個別トルクを失わず復元します。
    ///
    /// 責務: 1件の専門的な重整備記録が完全JSONとしてSQLiteを往復することを確認します。
    func testHeavyRecordRoundTripsPhotoAndFastenerEvidence() async throws {
        let repository = try GRDBMaintenanceRecordRepository(databaseQueue: DatabaseQueue())
        let photo = MaintenancePhoto(data: Data([0x01, 0x02]), caption: "Before")
        let evidence = FastenerInstallationEvidence(
            position: "Cylinder head A1",
            torqueNewtonMeters: 30,
            tool: "Torque wrench #1",
            tightenedBy: "Technician",
            tightenedAt: Date(timeIntervalSince1970: 500),
            photoIDs: [photo.id]
        )
        let record = MaintenanceRecord(
            vehicleID: VehicleID(),
            kind: .heavy,
            title: "Engine overhaul",
            workItems: [MaintenanceWorkItem(component: .engineAssembly, operation: .overhaul)],
            photos: [photo],
            fastenerGroups: [
                MaintenanceFastenerGroup(
                    name: "Cylinder head",
                    location: "Bank A",
                    expectedCount: 10,
                    removedCount: 10,
                    installations: [evidence]
                )
            ]
        )

        try await repository.save(record, for: "account-a")
        let records = try await repository.records(for: "account-a")
        let restored = try XCTUnwrap(records.first)

        XCTAssertEqual(restored, record)
        XCTAssertEqual(restored.fastenerGroups.first?.installations.first?.torqueNewtonMeters, 30)
        XCTAssertEqual(restored.fastenerGroups.first?.installations.first?.photoIDs, [photo.id])
    }

    /// アカウントごとの整備記録を分離します。
    ///
    /// 責務: 同じSQLite内でも別Appleアカウントの整備履歴が相互に見えないことを確認します。
    func testRecordsAreAccountScoped() async throws {
        let repository = try GRDBMaintenanceRecordRepository(databaseQueue: DatabaseQueue())
        let first = MaintenanceRecord(vehicleID: VehicleID(), kind: .light, title: "First")
        let second = MaintenanceRecord(vehicleID: VehicleID(), kind: .heavy, title: "Second")

        try await repository.save(first, for: "account-a")
        try await repository.save(second, for: "account-b")

        let firstRecords = try await repository.records(for: "account-a")
        let secondRecords = try await repository.records(for: "account-b")
        XCTAssertEqual(firstRecords.map(\.title), ["First"])
        XCTAssertEqual(secondRecords.map(\.title), ["Second"])
    }
}

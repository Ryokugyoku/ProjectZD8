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

    /// 同期済み集合で対象アカウントの記録だけを置き換えます。
    ///
    /// 責務: replaceAllが旧記録を削除して新集合を挿入し、他アカウントの行へ触れないことを確認します。
    func testReplaceAllReplacesOnlyTargetAccountRecords() async throws {
        let repository = try GRDBMaintenanceRecordRepository(databaseQueue: DatabaseQueue())
        let old = makeRecord(title: "Old", updatedAt: 100)
        let otherAccount = makeRecord(title: "Other", updatedAt: 150)
        try await repository.save(old, for: "account-a")
        try await repository.save(otherAccount, for: "account-b")
        let newer = makeRecord(title: "Newer", updatedAt: 300)
        let tombstone = makeRecord(title: "Deleted", updatedAt: 200, deletedAt: Date(timeIntervalSince1970: 200))

        try await repository.replaceAll([tombstone, newer], for: "account-a")

        let replaced = try await repository.records(for: "account-a")
        XCTAssertEqual(replaced.map(\.title), ["Newer", "Deleted"])
        XCTAssertEqual(replaced, [newer, tombstone])
        let untouched = try await repository.records(for: "account-b")
        XCTAssertEqual(untouched, [otherAccount])
    }

    /// 空集合での置換は対象アカウントの記録を全削除します。
    ///
    /// 責務: replaceAllへ空配列を渡した場合に旧記録が残らず他アカウントが保持されることを確認します。
    func testReplaceAllWithEmptySetClearsTargetAccount() async throws {
        let repository = try GRDBMaintenanceRecordRepository(databaseQueue: DatabaseQueue())
        try await repository.save(makeRecord(title: "A", updatedAt: 100), for: "account-a")
        let other = makeRecord(title: "B", updatedAt: 100)
        try await repository.save(other, for: "account-b")

        try await repository.replaceAll([], for: "account-a")

        let cleared = try await repository.records(for: "account-a")
        XCTAssertTrue(cleared.isEmpty)
        let retained = try await repository.records(for: "account-b")
        XCTAssertEqual(retained, [other])
    }

    /// 挿入に失敗した置換は1トランザクションとして巻き戻します。
    ///
    /// 責務: 同一IDの重複記録で挿入が失敗したとき、旧記録が削除されず残ることを確認します。
    func testReplaceAllRollsBackWhenInsertFails() async throws {
        let repository = try GRDBMaintenanceRecordRepository(databaseQueue: DatabaseQueue())
        let original = makeRecord(title: "Original", updatedAt: 100)
        try await repository.save(original, for: "account-a")
        let duplicated = makeRecord(title: "Duplicate", updatedAt: 200)

        do {
            try await repository.replaceAll([duplicated, duplicated], for: "account-a")
            XCTFail("重複IDの置換は失敗する必要があります")
        } catch let error as DatabaseError {
            XCTAssertEqual(error.resultCode, .SQLITE_CONSTRAINT)
        }

        let records = try await repository.records(for: "account-a")
        XCTAssertEqual(records, [original])
    }

    /// 壊れたJSON行の読込を明示的な失敗にします。
    ///
    /// 責務: payloadを復号できない行を空データや欠落へ潰さず、復号エラーとして伝えることを確認します。
    func testRecordsThrowsWhenStoredPayloadIsMalformed() async throws {
        let queue = try DatabaseQueue()
        let repository = try GRDBMaintenanceRecordRepository(databaseQueue: queue)
        try await queue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO maintenance_records
                        (id, accountIdentifier, vehicleID, kind, performedAt, updatedAt, deletedAt, payload)
                    VALUES ('r1', 'account-a', 'v1', 'light', 0, 0, NULL, ?)
                    """,
                arguments: [Data("not json".utf8)]
            )
        }

        do {
            _ = try await repository.records(for: "account-a")
            XCTFail("不正なpayloadの読込は失敗する必要があります")
        } catch is DecodingError {
            // 期待どおり復号エラーとして伝播する。
        }
        let otherAccount = try await repository.records(for: "account-b")
        XCTAssertTrue(otherAccount.isEmpty)
    }

    /// 更新日時だけを指定した固定の整備記録を生成します。
    ///
    /// 責務: 並び順検証用に表題と更新日時、削除日時だけが異なる記録を提供します。
    /// - Parameters:
    ///   - title: 記録の表題。
    ///   - updatedAt: 更新日時の1970年からの秒数。
    ///   - deletedAt: 墓石日時。通常記録では `nil`。
    /// - Returns: 新規IDを持つ軽整備記録。
    private func makeRecord(title: String, updatedAt: TimeInterval, deletedAt: Date? = nil) -> MaintenanceRecord {
        MaintenanceRecord(
            vehicleID: VehicleID(),
            kind: .light,
            title: title,
            performedAt: Date(timeIntervalSince1970: 50),
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            deletedAt: deletedAt
        )
    }
}

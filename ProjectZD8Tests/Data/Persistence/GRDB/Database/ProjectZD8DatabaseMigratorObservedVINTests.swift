import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `release_v1_add_connection_session_observed_vin` の既存行保全と `observedVIN` 列のCHECK制約を検証します。
///
/// SQLは固定リテラルと引数バインドだけで組み立てます。
final class ProjectZD8DatabaseMigratorObservedVINTests: XCTestCase {
    /// 観測VIN列を追加する直前のMigration識別子です。
    private static let previousMigration = "release_v1_add_connection_session_segments_gaps_can_frames"
    /// 検証対象のMigration識別子です。
    private static let observedVINMigration = "release_v1_add_connection_session_observed_vin"

    /// 観測VINを指定してセッション行を直接挿入します。
    ///
    /// 責務: 1件の `connection_sessions` 行を観測VIN付きで固定SQLから追加します。
    /// - Parameters:
    ///   - database: 書込み中の接続。
    ///   - id: セッションID。
    ///   - observedVIN: 挿入する観測VIN。
    /// - Throws: SQLite書込み失敗(制約違反を含む)。
    private func insertSession(_ database: Database, id: String = SegmentationSchemaFixtures.sessionA, observedVIN: String?) throws {
        try database.execute(
            sql: "INSERT INTO connection_sessions (id, accountIdentifier, startedAt, observedVIN) VALUES (?, 'account', ?, ?)",
            arguments: [id, Date(timeIntervalSince1970: 100), observedVIN]
        )
    }

    /// 観測VIN列を直接更新します。
    ///
    /// 責務: 1件の既存セッション行の `observedVIN` を固定SQLで書き換えます。
    /// - Parameters:
    ///   - database: 書込み中の接続。
    ///   - observedVIN: 書き込む観測VIN。
    /// - Throws: SQLite更新失敗(制約違反を含む)。
    private func updateObservedVIN(_ database: Database, to observedVIN: String?) throws {
        try database.execute(
            sql: "UPDATE connection_sessions SET observedVIN = ? WHERE id = ?",
            arguments: [observedVIN, SegmentationSchemaFixtures.sessionA]
        )
    }

    /// 指定セッション行の観測VINを読みます。
    ///
    /// 責務: 1件の行の `observedVIN` 列を固定SQLで返します。
    /// - Parameter queue: 読取対象のDB Queue。
    /// - Returns: 保存済みの観測VIN。
    /// - Throws: SQLite読込失敗。
    private func storedObservedVIN(_ queue: DatabaseQueue) throws -> String? {
        try queue.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT observedVIN FROM connection_sessions WHERE id = ?",
                arguments: [SegmentationSchemaFixtures.sessionA]
            )
        }
    }

    // MARK: - upgrade

    /// 適用前から存在したセッション行は観測VINがNULLになり、他の列は変わりません。
    ///
    /// 責務: 旧スキーマで作った行の全列値がMigration前後で一致し、追加列だけがNULLであることを確認します。
    func testUpgradeLeavesExistingSessionColumnsUnchangedAndObservedVINNull() throws {
        let queue = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(queue, upTo: Self.previousMigration)
        try queue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO connection_sessions
                    (id, accountIdentifier, startedAt, endedAt, endReason, vehicleID, vehicleName, vehicleDisplayIdentifier)
                    VALUES (?, 'account', ?, ?, 'userDisconnected', ?, 'BRZ', 'ZD8')
                    """,
                arguments: [
                    SegmentationSchemaFixtures.sessionA,
                    Date(timeIntervalSince1970: 100),
                    Date(timeIntervalSince1970: 200),
                    "00000000-0000-0000-0000-0000000000f1"
                ]
            )
        }
        let before = try queue.read { try XCTUnwrap(try Row.fetchOne($0, sql: "SELECT * FROM connection_sessions")) }
        XCTAssertFalse(before.hasColumn("observedVIN"))

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue, upTo: Self.observedVINMigration)

        let after = try queue.read { try XCTUnwrap(try Row.fetchOne($0, sql: "SELECT * FROM connection_sessions")) }
        XCTAssertTrue(after.hasColumn("observedVIN"))
        XCTAssertEqual(after["observedVIN"] as DatabaseValue, .null)
        for column in before.columnNames {
            XCTAssertEqual(after[column] as DatabaseValue, before[column] as DatabaseValue, "column: \(column)")
        }
        XCTAssertEqual(Set(after.columnNames), Set(before.columnNames).union(["observedVIN"]))
    }

    // MARK: - CHECK constraint (accepted)

    /// 前後に空白のない値、内側に空白を含む値、NULLは直接INSERTで受け付けます。
    ///
    /// 責務: 制約が正規形の値まで拒否しない(拒否テストが常に失敗する状態でない)ことを確認します。
    func testCheckAcceptsTrimmedValueInnerWhitespaceAndNull() throws {
        let fixtures = try SegmentationSchemaFixtures()

        try fixtures.queue.write { database in
            try insertSession(database, observedVIN: "jf1 ZD8abc")
            try insertSession(database, id: SegmentationSchemaFixtures.sessionB, observedVIN: nil)
        }

        XCTAssertEqual(try storedObservedVIN(fixtures.queue), "jf1 ZD8abc")
    }

    // MARK: - CHECK constraint (rejected)

    /// 空文字は直接INSERTで拒否されます。
    ///
    /// 責務: 長さ0の観測VINがスキーマ制約で保存できないことを確認します。
    func testCheckRejectsEmptyStringOnInsert() throws {
        let fixtures = try SegmentationSchemaFixtures()

        fixtures.assertRejected { try self.insertSession($0, observedVIN: "") }
    }

    /// 前または後ろに空白がある値は直接INSERTで拒否されます。
    ///
    /// 責務: 前空白・後空白・空白だけの各値がスキーマ制約で保存できないことを確認します。
    func testCheckRejectsLeadingTrailingAndOnlySpacesOnInsert() throws {
        let fixtures = try SegmentationSchemaFixtures()

        fixtures.assertRejected { try self.insertSession($0, observedVIN: " JF1ZD8") }
        fixtures.assertRejected { try self.insertSession($0, observedVIN: "JF1ZD8 ") }
        fixtures.assertRejected { try self.insertSession($0, observedVIN: "   ") }
    }

    /// 前または後ろにタブ・改行がある値も直接INSERTで拒否されます。
    ///
    /// 責務: Domainの正規化(空白・改行の除去)と同じ範囲の空白類がスキーマ制約でも拒否されることを確認します。
    func testCheckRejectsLeadingOrTrailingTabAndNewlineOnInsert() throws {
        let fixtures = try SegmentationSchemaFixtures()

        fixtures.assertRejected { try self.insertSession($0, observedVIN: "\tJF1ZD8") }
        fixtures.assertRejected { try self.insertSession($0, observedVIN: "JF1ZD8\n") }
    }

    /// 既存行の観測VINを空文字・前後空白付きへ直接UPDATEすると拒否され、元の値が残ります。
    ///
    /// 責務: 更新経路でも同じCHECK制約が働くことを確認します。
    func testCheckRejectsEmptyAndPaddedValuesOnUpdate() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { try insertSession($0, observedVIN: "JF1ZD8") }

        fixtures.assertRejected { try self.updateObservedVIN($0, to: "") }
        fixtures.assertRejected { try self.updateObservedVIN($0, to: " JF1ZD8") }
        fixtures.assertRejected { try self.updateObservedVIN($0, to: "JF1ZD8 ") }

        XCTAssertEqual(try storedObservedVIN(fixtures.queue), "JF1ZD8")
    }
}

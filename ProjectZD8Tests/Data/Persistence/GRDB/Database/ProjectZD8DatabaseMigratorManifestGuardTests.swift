import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 6件目のMigrationで作り直した `acquisition_manifest_update_guard` が既存8列の変更を列ごとに拒否し、旧スキーマで作った行にも効き、
/// 5件目・6件目の前後で他の10トリガーの定義が変わらないことを検証します。
///
/// 仕様: U6 受け入れ条件 1〜3(B5)。拒否はトリガーの `RAISE(ABORT, ...)`(`SQLITE_CONSTRAINT` と固定の文言)で確かめます。
/// SQLは固定リテラルと引数バインドだけで組み立てます。
final class ProjectZD8DatabaseMigratorManifestGuardTests: XCTestCase {
    /// 4件目のMigration識別子です。
    private static let fourthMigration = "release_v1_add_connection_session_segments_gaps_can_frames"
    /// 5件目のMigration識別子です。
    private static let fifthMigration = "release_v1_add_connection_session_observed_vin"
    /// 作り直したトリガーの名前です。
    private static let recreatedTrigger = "acquisition_manifest_update_guard"
    /// トリガーが拒否する時の文言です。
    private static let immutableMessage = "acquisition manifest is immutable"

    /// 既存8列のうち1列を変える固定の UPDATE 文(封印遷移と同時)です。列名と、どの列を変えたかの説明の組です。
    private static let sealWithColumnChange: [(column: String, sql: String)] = [
        ("sessionID", "UPDATE connection_session_acquisition_manifests SET isSealed = 1, sessionID = ? WHERE sessionID = ?"),
        ("manifestVersion", "UPDATE connection_session_acquisition_manifests SET isSealed = 1, manifestVersion = 2 WHERE sessionID = ?"),
        (
            "applicationMarketingVersion",
            "UPDATE connection_session_acquisition_manifests SET isSealed = 1, applicationMarketingVersion = 'other' WHERE sessionID = ?"
        ),
        (
            "applicationBuildVersion",
            "UPDATE connection_session_acquisition_manifests SET isSealed = 1, applicationBuildVersion = '2' WHERE sessionID = ?"
        ),
        ("schemaContractVersion", "UPDATE connection_session_acquisition_manifests SET isSealed = 1, schemaContractVersion = 2 WHERE sessionID = ?"),
        ("pollingPolicyVersion", "UPDATE connection_session_acquisition_manifests SET isSealed = 1, pollingPolicyVersion = 2 WHERE sessionID = ?"),
        ("acquisitionPlatform", "UPDATE connection_session_acquisition_manifests SET isSealed = 1, acquisitionPlatform = 'iOS' WHERE sessionID = ?"),
        (
            "modelInputManifestVersion",
            "UPDATE connection_session_acquisition_manifests SET isSealed = 1, modelInputManifestVersion = 2 WHERE sessionID = ?"
        ),
    ]

    /// 旧スキーマにもある列だけで親セッション行を挿入します。
    ///
    /// 責務: Migration途中のDBでも通る固定SQLで1件の `connection_sessions` 行を追加します。
    private func insertSession(_ database: Database, id: String) throws {
        try database.execute(
            sql: "INSERT INTO connection_sessions (id, accountIdentifier, startedAt) VALUES (?, 'account', ?)",
            arguments: [id, Date(timeIntervalSince1970: 90)]
        )
    }

    /// 旧スキーマにもある列だけで、封印の前提(PID 1件・開始境界)をそろえた未封印のmanifestを挿入します。
    ///
    /// 責務: 封印遷移だけなら通る状態の1件のmanifestを作ります。
    private func insertSealableManifest(_ database: Database, id: String) throws {
        try database.execute(
            sql: """
                INSERT INTO connection_session_acquisition_manifests
                (sessionID, manifestVersion, applicationMarketingVersion, applicationBuildVersion, schemaContractVersion,
                 pollingPolicyVersion, acquisitionPlatform, modelInputManifestVersion, isSealed)
                VALUES (?, 1, 'fixture', '1', 1, 1, 'macOS', 1, 0)
                """,
            arguments: [id]
        )
        try database.execute(
            sql: """
                INSERT INTO connection_session_acquisition_pid_definitions
                (sessionID, service, pid, capabilitySupport, isCollectionEnabled, definitionRevision, requiredByteCount,
                 formulaCanonicalizationVersion, formulaExpression, unit, validityRangeKind, minimumValue, maximumValue)
                VALUES (?, 1, 12, 'supported', 1, 1, 2, 1, 'A', 'rpm', 'notDeclared', NULL, NULL)
                """,
            arguments: [id]
        )
        try database.execute(
            sql: "INSERT INTO connection_session_acquisition_ordered_pids (sessionID, ordinal, service, pid) VALUES (?, 0, 1, 12)",
            arguments: [id]
        )
        try database.execute(
            sql: """
                INSERT INTO connection_session_acquisition_raw_boundaries
                (sessionID, eventKind, occurredAtMicroseconds, endReason) VALUES (?, 'started', 100000000, NULL)
                """,
            arguments: [id]
        )
    }

    /// manifestを封印します。
    ///
    /// 責務: `isSealed` だけを1へ更新します。
    private func seal(_ database: Database, id: String) throws {
        try database.execute(sql: "UPDATE connection_session_acquisition_manifests SET isSealed = 1 WHERE sessionID = ?", arguments: [id])
    }

    /// 書込みがトリガーで拒否されることを確かめます。
    ///
    /// 責務: `SQLITE_CONSTRAINT` で、かつトリガーの文言で失敗すること(外部キーなど他の制約でないこと)を確認します。
    private func assertRejectedByGuard(
        _ queue: DatabaseQueue, _ message: String, file: StaticString = #filePath, line: UInt = #line, _ body: (Database) throws -> Void
    ) {
        XCTAssertThrowsError(try queue.write(body), message, file: file, line: line) { error in
            let databaseError = error as? DatabaseError
            XCTAssertEqual(databaseError?.resultCode, .SQLITE_CONSTRAINT, "\(message): \(error)", file: file, line: line)
            XCTAssertEqual(databaseError?.message, Self.immutableMessage, "\(message): \(error)", file: file, line: line)
        }
    }

    /// manifest行の封印状態と、既存8列の保存値を読みます。
    ///
    /// 責務: 拒否の後に行が変わっていないことを確かめるための値を返します。
    private func storedValues(_ queue: DatabaseQueue, id: String) throws -> [DatabaseValue] {
        let row = try queue.read { database in
            try Row.fetchOne(
                database,
                sql: """
                    SELECT isSealed, sessionID, manifestVersion, applicationMarketingVersion, applicationBuildVersion,
                           schemaContractVersion, pollingPolicyVersion, acquisitionPlatform, modelInputManifestVersion
                    FROM connection_session_acquisition_manifests WHERE sessionID = ?
                    """,
                arguments: [id]
            )
        }
        return try XCTUnwrap(row).databaseValues.map { $0 }
    }

    /// 封印遷移と同時に既存8列のどれか1つを変える UPDATE を列ごとに拒否し、行は未封印のまま変わりません。
    ///
    /// 責務: 全Migration適用後のDBで、8列それぞれの拒否と保存値の不変、同じ前提での正当な封印の成功(対照)を確認します(受け入れ条件 1)。
    func testSealTransitionChangingAnyExistingColumnIsRejected() throws {
        let fixtures = try SegmentationSchemaFixtures()
        let id = SegmentationSchemaFixtures.sessionA
        try fixtures.queue.write { database in
            try insertSession(database, id: id)
            try insertSession(database, id: SegmentationSchemaFixtures.sessionB)
            try insertSealableManifest(database, id: id)
        }
        let before = try storedValues(fixtures.queue, id: id)

        for change in Self.sealWithColumnChange {
            let arguments: StatementArguments = change.column == "sessionID" ? [SegmentationSchemaFixtures.sessionB, id] : [id]
            assertRejectedByGuard(fixtures.queue, change.column) { try $0.execute(sql: change.sql, arguments: arguments) }
            XCTAssertEqual(try storedValues(fixtures.queue, id: id), before, change.column)
        }

        try fixtures.queue.write { try seal($0, id: id) }
        XCTAssertEqual(try storedValues(fixtures.queue, id: id).first, 1.databaseValue, "列を変えない封印は通る")
    }

    /// 4件目・5件目まで適用した旧スキーマで作った行を残して全件適用すると、封印済みの行の更新と、未封印の行の不正な更新が拒否されます。
    ///
    /// 責務: 旧スキーマの封印済み1件・未封印1件について、更新・封印の解除・封印を伴わない列の変更・封印と同時の列の変更を拒否し、
    /// 未封印の行の正当な封印は通ることを確認します(受け入れ条件 2)。
    func testLegacyRowsAreGuardedAfterFullMigration() throws {
        for legacyMigration in [Self.fourthMigration, Self.fifthMigration] {
            let queue = try DatabaseQueue()
            try ProjectZD8DatabaseMigrator.migrator.migrate(queue, upTo: legacyMigration)
            let sealed = SegmentationSchemaFixtures.sessionA
            let unsealed = SegmentationSchemaFixtures.sessionB
            try queue.write { database in
                try insertSession(database, id: sealed)
                try insertSession(database, id: unsealed)
                try insertSealableManifest(database, id: sealed)
                try seal(database, id: sealed)
                try insertSealableManifest(database, id: unsealed)
            }

            try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

            try assertLegacyRowsGuarded(queue, sealed: sealed, unsealed: unsealed, label: legacyMigration)
        }
    }

    /// 全件適用後の旧スキーマの行に対する拒否と、正当な封印を確かめます。
    ///
    /// 責務: `testLegacyRowsAreGuardedAfterFullMigration` の1つのDBについて検証します。
    private func assertLegacyRowsGuarded(_ queue: DatabaseQueue, sealed: String, unsealed: String, label: String) throws {
        let sealedBefore = try storedValues(queue, id: sealed)
        assertRejectedByGuard(queue, "\(label) 封印済みの列の更新") {
            try $0.execute(
                sql: "UPDATE connection_session_acquisition_manifests SET applicationBuildVersion = '2' WHERE sessionID = ?",
                arguments: [sealed]
            )
        }
        assertRejectedByGuard(queue, "\(label) 封印の解除") {
            try $0.execute(sql: "UPDATE connection_session_acquisition_manifests SET isSealed = 0 WHERE sessionID = ?", arguments: [sealed])
        }
        assertRejectedByGuard(queue, "\(label) 封印済みのチップ種別の追記") {
            try $0.execute(
                sql: "UPDATE connection_session_acquisition_manifests SET adapterChipFamily = 'stn' WHERE sessionID = ?",
                arguments: [sealed]
            )
        }
        XCTAssertEqual(try storedValues(queue, id: sealed), sealedBefore, label)

        let unsealedBefore = try storedValues(queue, id: unsealed)
        assertRejectedByGuard(queue, "\(label) 未封印の封印を伴わない変更") {
            try $0.execute(sql: "UPDATE connection_session_acquisition_manifests SET manifestVersion = 2 WHERE sessionID = ?", arguments: [unsealed])
        }
        assertRejectedByGuard(queue, "\(label) 未封印の封印と同時の変更") {
            try $0.execute(
                sql: "UPDATE connection_session_acquisition_manifests SET isSealed = 1, pollingPolicyVersion = 2 WHERE sessionID = ?",
                arguments: [unsealed]
            )
        }
        XCTAssertEqual(try storedValues(queue, id: unsealed), unsealedBefore, label)

        try queue.write { try seal($0, id: unsealed) }
        XCTAssertEqual(try storedValues(queue, id: unsealed).first, 1.databaseValue, "\(label) 列を変えない封印は通る")
    }

    /// 作り直した1件を除く他の10トリガーの定義は、5件目・6件目の適用前後で変わりません。
    ///
    /// 責務: 4件目適用時点の10件を、5件目適用後・全件適用後と `sqlite_master` の名前・所属表・SQLで比べ、全件適用後に11件あることを確認します(受け入れ条件 3)。
    func testOtherTriggersAreUnchangedByFifthAndSixthMigrations() throws {
        let queue = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(queue, upTo: Self.fourthMigration)
        let before = try triggerDefinitions(queue).filter { $0.key != Self.recreatedTrigger }
        XCTAssertEqual(before.count, 10)

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue, upTo: Self.fifthMigration)
        XCTAssertEqual(try triggerDefinitions(queue).filter { $0.key != Self.recreatedTrigger }, before, "5件目")

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)
        let after = try triggerDefinitions(queue)
        XCTAssertEqual(after.filter { $0.key != Self.recreatedTrigger }, before, "6件目")
        XCTAssertEqual(after.count, 11)
        XCTAssertNotNil(after[Self.recreatedTrigger])
    }

    /// トリガーの名前から「所属表|SQL」への対応を読みます。
    ///
    /// 責務: `sqlite_master` の全トリガー定義を返します。
    private func triggerDefinitions(_ queue: DatabaseQueue) throws -> [String: String] {
        try queue.read { database in
            let rows = try Row.fetchAll(database, sql: "SELECT name, tbl_name, sql FROM sqlite_master WHERE type = 'trigger'")
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                let name: String = row["name"]
                let table: String = row["tbl_name"]
                let sql: String = row["sql"]
                return (name, table + "|" + sql)
            })
        }
    }
}

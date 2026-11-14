import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 4件目のセグメント系Migrationの登録・新規適用・既存データを持つDBへの適用を検証します。
final class ProjectZD8DatabaseMigratorSegmentationUpgradeTests: XCTestCase {
    /// 4件目の直前までの適用済みを表すMigration識別子です。
    private static let thirdMigration = "release_v1_add_connection_session_acquisition_batch_evidence"

    /// 新規DBへ全件適用すると3つの新表が作成されます。
    ///
    /// 責務: 全Migrationが成功し、セグメント・欠損・CANフレーム表が存在し空であることを確認します。
    func testFreshDatabaseCreatesSegmentationTables() throws {
        let queue = try DatabaseQueue()

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        try queue.read { database in
            XCTAssertTrue(try database.tableExists("connection_session_segments"))
            XCTAssertTrue(try database.tableExists("connection_session_gaps"))
            XCTAssertTrue(try database.tableExists("connection_session_can_frames"))
            XCTAssertEqual(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM connection_session_segments"), 0)
            XCTAssertEqual(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM connection_session_gaps"), 0)
            XCTAssertEqual(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM connection_session_can_frames"), 0)
        }
    }

    /// 3件目までの適用時点では新表とRaw追加列が存在しません。
    ///
    /// 責務: 「適用前後の比較」が空振りしないよう、3件目時点の状態が4件目の成果物を含まないことを確認します。
    func testThirdMigrationStateHasNoSegmentationSchema() throws {
        let queue = try DatabaseQueue()

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue, upTo: Self.thirdMigration)

        try queue.read { database in
            XCTAssertFalse(try database.tableExists("connection_session_segments"))
            XCTAssertFalse(try database.tableExists("connection_session_gaps"))
            XCTAssertFalse(try database.tableExists("connection_session_can_frames"))
            let columns = try database.columns(in: "connection_session_raw_logs").map(\.name)
            XCTAssertFalse(columns.contains("segmentOrdinal"))
            XCTAssertFalse(columns.contains("monotonicNanoseconds"))
        }
    }

    /// Raw表に追加された2列はINTEGERでNULL可です。
    ///
    /// 責務: `segmentOrdinal` と `monotonicNanoseconds` の列の存在・型・NULL許容を確認します。
    func testRawLogSegmentColumnsAreNullableIntegers() throws {
        let queue = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        let columns = try queue.read { try $0.columns(in: "connection_session_raw_logs") }

        for name in ["segmentOrdinal", "monotonicNanoseconds"] {
            let column = try XCTUnwrap(columns.first { $0.name == name }, name)
            XCTAssertEqual(column.type.uppercased(), "INTEGER", name)
            XCTAssertFalse(column.isNotNull, name)
            XCTAssertNil(column.defaultValueSQL, name)
        }
    }

    /// 既存のセッション行とRaw行は4件目の適用後も内容が変わりません。
    ///
    /// 責務: 3件適用済みDBへ4件目を適用し、既存行の全列保持と追加列のNULLを確認します。
    func testUpgradePreservesExistingSessionAndRawRows() throws {
        let queue = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(queue, upTo: Self.thirdMigration)
        try insertLegacyRows(queue)
        let sessionBefore = try queue.read { try Row.fetchAll($0, sql: "SELECT * FROM connection_sessions") }
        let rawBefore = try queue.read { try Row.fetchAll($0, sql: "SELECT * FROM connection_session_raw_logs") }
        XCTAssertEqual(sessionBefore.count, 1)
        XCTAssertEqual(rawBefore.count, 2)

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        try queue.read { database in
            let sessionAfter = try Row.fetchAll(database, sql: "SELECT * FROM connection_sessions")
            XCTAssertEqual(sessionAfter, sessionBefore)
            let rawAfter = try Row.fetchAll(database, sql: "SELECT * FROM connection_session_raw_logs ORDER BY sequence")
            XCTAssertEqual(rawAfter.count, rawBefore.count)
            for (before, after) in zip(rawBefore, rawAfter) {
                for column in before.columnNames {
                    XCTAssertEqual(after[column] as DatabaseValue, before[column] as DatabaseValue, column)
                }
                XCTAssertTrue((after["segmentOrdinal"] as DatabaseValue).isNull)
                XCTAssertTrue((after["monotonicNanoseconds"] as DatabaseValue).isNull)
            }
            XCTAssertEqual(rawAfter[1]["payload"] as Data?, Data([0x01, 0x02]))
            XCTAssertEqual(rawAfter[1]["batchElapsedNanoseconds"] as Int64?, 2_000)
        }
    }

    /// 既存テーブルのトリガー定義は4件目の適用前後で同一です。
    ///
    /// 責務: `sqlite_master` のトリガー名・所属表・SQLを3件適用時点と4件適用後で比較します。
    func testExistingTriggersAreUnchangedByFourthMigration() throws {
        let queue = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(queue, upTo: Self.thirdMigration)
        let before = try triggerDefinitions(queue)
        XCTAssertFalse(before.isEmpty)

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        XCTAssertEqual(try triggerDefinitions(queue), before)
    }

    /// 3件適用済みDBへ旧来のセッション1件とRaw行2件を挿入します。
    ///
    /// 責務: 4件目適用前の既存データを固定値で作ります。
    /// - Parameter queue: 3件適用済みのDB Queue。
    /// - Throws: SQLite書込み失敗。
    private func insertLegacyRows(_ queue: DatabaseQueue) throws {
        try queue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO connection_sessions (id, accountIdentifier, startedAt, endedAt, endReason)
                    VALUES ('legacy-session', 'account', ?, ?, 'userDisconnected')
                    """,
                arguments: [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 101)]
            )
            try insertLegacyRaw(database, sequence: 0, elapsed: 1_000, payload: Data([0x01]))
            try insertLegacyRaw(database, sequence: 1, elapsed: 2_000, payload: Data([0x01, 0x02]))
        }
    }

    /// 旧来のRaw行を1件挿入します。
    ///
    /// 責務: 追加列を指定しない形式の `connection_session_raw_logs` 行を追加します。
    /// - Parameters:
    ///   - database: 書込み中の接続。
    ///   - sequence: 記録順序。
    ///   - elapsed: バッチ経過ナノ秒。
    ///   - payload: 応答payload。
    /// - Throws: SQLite書込み失敗。
    private func insertLegacyRaw(_ database: Database, sequence: Int64, elapsed: Int64, payload: Data) throws {
        try database.execute(
            sql: """
                INSERT INTO connection_session_raw_logs
                (sessionID, sequence, observedAt, batchElapsedNanoseconds, service, pid, payload)
                VALUES ('legacy-session', ?, '2026-01-01 00:00:00.000', ?, 1, 12, ?)
                """,
            arguments: [sequence, elapsed, payload]
        )
    }

    /// 全トリガーの定義を名前順で返します。
    ///
    /// 責務: `sqlite_master` からトリガーの名前・所属表・SQLを固定SQLで取得します。
    /// - Parameter queue: 読取対象のDB Queue。
    /// - Returns: 名前順の定義文字列。
    /// - Throws: SQLite読込失敗。
    private func triggerDefinitions(_ queue: DatabaseQueue) throws -> [String] {
        try queue.read { database in
            try Row.fetchAll(
                database,
                sql: "SELECT name, tbl_name, sql FROM sqlite_master WHERE type = 'trigger' ORDER BY name"
            ).map { row in
                let name: String = row["name"]
                let table: String = row["tbl_name"]
                let sql: String = row["sql"]
                return [name, table, sql].joined(separator: "|")
            }
        }
    }
}

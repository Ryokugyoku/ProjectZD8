import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `release_v1_add_connection_session_location_track_sync_states` の表の構造・制約と、直前の Migration からの移行を検証します。
///
/// SQLは固定リテラルと引数バインドだけで組み立てます。
final class ProjectZD8DatabaseMigratorLocationTrackSyncTests: XCTestCase {
    /// 同期記録表の直前に登録されている識別子です。
    private static let previousMigration = "release_v1_add_connection_session_location_samples_and_events"
    /// 同期記録表の Migration 識別子です。
    private static let syncMigration = "release_v1_add_connection_session_location_track_sync_states"
    /// 同期記録表の名前です。
    private static let table = "connection_session_location_track_sync_states"
    /// 同期記録表に期待する列名です。
    private static let columns: Set<String> = [
        "sessionID", "origin", "manifestDigest", "sampleCount", "lastSampleSequence",
        "eventCount", "lastEventOrdinal", "syncedAtMicroseconds"
    ]

    /// 同期記録行の既定値です。各テストは1項目だけ差し替えます。
    private struct SyncRow {
        var session = SegmentationSchemaFixtures.sessionA
        var origin = "uploaded"
        var digest = String(repeating: "a", count: 64)
        var sampleCount: Int64 = 2
        var lastSample: Int64? = 1
        var eventCount: Int64 = 1
        var lastEvent: Int64? = 0
    }

    /// 全Migration適用済みで親セッション `sessionA` を1件持つ組立てを返します。
    ///
    /// 責務: 外部キーの参照先となるセッションを用意します。
    /// - Throws: DB作成またはセッション挿入の失敗。
    private func makeFixtures() throws -> SegmentationSchemaFixtures {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { try fixtures.insertSession($0) }
        return fixtures
    }

    /// 同期記録の行を直接挿入します。
    ///
    /// 責務: 1件の行を引数バインドで追加します。
    /// - Parameters:
    ///   - database: 書込み中の接続。
    ///   - row: 挿入する値。
    /// - Throws: SQLite書込み失敗(制約違反を含む)。
    private func insert(_ database: Database, _ row: SyncRow) throws {
        let values: [(any DatabaseValueConvertible)?] = [
            row.session, row.origin, row.digest, row.sampleCount, row.lastSample, row.eventCount, row.lastEvent, 1_000_000
        ]
        try database.execute(
            sql: """
                INSERT INTO connection_session_location_track_sync_states
                (sessionID, origin, manifestDigest, sampleCount, lastSampleSequence, eventCount, lastEventOrdinal, syncedAtMicroseconds)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: StatementArguments(values)
        )
    }

    /// 書込みが指定の拡張結果コードで拒否されることを検証します。
    ///
    /// 責務: 成功や別種のエラーでなく、期待した種類の制約違反で失敗したことを確認します。
    /// - Parameters:
    ///   - fixtures: 検証用の組立て。
    ///   - label: 失敗時に添える説明。
    ///   - code: 期待する拡張結果コード。
    ///   - row: 挿入を試みる行。
    private func assertRejected(
        _ fixtures: SegmentationSchemaFixtures,
        _ label: String,
        code: ResultCode = .SQLITE_CONSTRAINT_CHECK,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ row: SyncRow
    ) {
        XCTAssertThrowsError(try fixtures.queue.write { try insert($0, row) }, label, file: file, line: line) { error in
            XCTAssertEqual((error as? DatabaseError)?.extendedResultCode, code, "\(label): \(error)", file: file, line: line)
        }
    }

    /// 全Migrationを適用すると、期待する列・NULL許容・主キーで作成されます。
    ///
    /// 責務: 列名の集合、NULLを許す列、主キー、行が空であることを確認します。
    func testFullMigrationCreatesTableWithExpectedColumns() throws {
        let queue = try DatabaseQueue()

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        try queue.read { database in
            XCTAssertTrue(try database.tableExists(Self.table))
            let columns = try database.columns(in: Self.table)
            XCTAssertEqual(Set(columns.map(\.name)), Self.columns)
            XCTAssertEqual(Set(columns.filter { !$0.isNotNull }.map(\.name)), ["lastSampleSequence", "lastEventOrdinal"])
            XCTAssertEqual(try database.primaryKey(Self.table).columns, ["sessionID"])
            XCTAssertEqual(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM connection_session_location_track_sync_states"), 0)
        }
    }

    /// 親は connection_sessions で、削除は CASCADE です。
    ///
    /// 責務: 外部キーの参照先と ON DELETE の動作を、定義の問い合わせで確認します。
    func testForeignKeyReferencesSessionsWithCascade() throws {
        let queue = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        let rows = try queue.read {
            try Row.fetchAll($0, sql: "SELECT \"table\", \"from\", on_delete FROM pragma_foreign_key_list(?)", arguments: [Self.table])
        }

        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row["table"] as String, "connection_sessions")
        XCTAssertEqual(row["from"] as String, "sessionID")
        XCTAssertEqual(row["on_delete"] as String, "CASCADE")
    }

    /// 直前の Migration までではこの表が無く、この Migration の直後に登録されています。
    ///
    /// 責務: 直前時点の状態の確認と、全適用後の識別子の並びで直前の次にあることを確認します。
    func testPreviousStateHasNoTableAndMigrationIsRegisteredRightAfter() throws {
        let previous = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(previous, upTo: Self.previousMigration)
        XCTAssertFalse(try previous.read { try $0.tableExists(Self.table) })
        let appliedBefore = try previous.read { try ProjectZD8DatabaseMigrator.migrator.appliedIdentifiers($0) }
        XCTAssertFalse(appliedBefore.contains(Self.syncMigration))

        let full = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(full)
        let applied = try full.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid") }

        let previousIndex = try XCTUnwrap(applied.firstIndex(of: Self.previousMigration))
        XCTAssertEqual(applied.dropFirst(previousIndex + 1).first, Self.syncMigration)
    }

    /// 直前まで適用済みのDBを最新へ移行しても、既存のセッションと位置の行は変わらず、同期記録を保存できます。
    ///
    /// 責務: 移行前後のセッション行の一致、位置の保持、移行後の同期記録の保存と読出しを確認します。
    func testUpgradePreservesSessionsAndAcceptsSyncRecords() throws {
        let queue = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(queue, upTo: Self.previousMigration)
        try queue.write { database in
            try database.execute(
                sql: "INSERT INTO connection_sessions (id, accountIdentifier, startedAt) VALUES (?, 'account', ?)",
                arguments: [SegmentationSchemaFixtures.sessionA, Date(timeIntervalSince1970: 90)]
            )
        }
        let before = try queue.read { try Row.fetchAll($0, sql: "SELECT * FROM connection_sessions") }
        XCTAssertEqual(before.count, 1)

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        XCTAssertEqual(try queue.read { try Row.fetchAll($0, sql: "SELECT * FROM connection_sessions") }, before)
        let sessionID = ConnectionSessionID(rawValue: try XCTUnwrap(UUID(uuidString: SegmentationSchemaFixtures.sessionA)))
        let repository = try GRDBConnectionSessionLocationTrackSyncRepository(databaseQueue: queue)
        let mark = ConnectionSessionLocationTrackValueFixtures.contiguousWatermark(samples: 1, events: 0)
        try repository.markUploaded(
            sessionID: sessionID, manifestDigest: ConnectionSessionLocationTrackValueFixtures.digest(), watermark: mark, at: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(try repository.syncRecord(for: sessionID)?.watermark, mark)
    }

    /// 既定の行と、境界値の行は挿入できます。
    ///
    /// 責務: 以降の拒否テストの対照として、64文字のダイジェスト・origin の2値・事象だけ/サンプルだけの行が受け入れられることを確認します。
    func testDefaultAndBoundaryRowsAreAccepted() throws {
        let fixtures = try makeFixtures()
        try fixtures.queue.write { try fixtures.insertSession($0, id: SegmentationSchemaFixtures.sessionB) }

        try fixtures.queue.write { try insert($0, SyncRow()) }
        try fixtures.queue.write { try insert($0, SyncRow(session: SegmentationSchemaFixtures.sessionB, origin: "restored", sampleCount: 0, lastSample: nil)) }

        XCTAssertEqual(try fixtures.queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM connection_session_location_track_sync_states") }, 2)
        let eventsOnly = SyncRow(sampleCount: 0, lastSample: nil)
        let samplesOnly = SyncRow(eventCount: 0, lastEvent: nil)
        try fixtures.queue.write { try $0.execute(sql: "DELETE FROM connection_session_location_track_sync_states") }
        XCTAssertNoThrow(try fixtures.queue.write { try insert($0, eventsOnly) })
        try fixtures.queue.write { try $0.execute(sql: "DELETE FROM connection_session_location_track_sync_states") }
        XCTAssertNoThrow(try fixtures.queue.write { try insert($0, samplesOnly) })
    }

    /// origin は uploaded と restored 以外を拒否します。
    ///
    /// 責務: 未知の値と空文字が CHECK で拒否されることを確認します。
    func testUnknownOriginIsRejected() throws {
        let fixtures = try makeFixtures()

        assertRejected(fixtures, "unknown origin", SyncRow(origin: "synced"))
        assertRejected(fixtures, "empty origin", SyncRow(origin: ""))
    }

    /// ダイジェストは64文字だけを受け入れます。
    ///
    /// 責務: 63文字・65文字・空が CHECK で拒否されることを確認します。
    func testDigestLengthOtherThan64IsRejected() throws {
        let fixtures = try makeFixtures()

        assertRejected(fixtures, "63 chars", SyncRow(digest: String(repeating: "a", count: 63)))
        assertRejected(fixtures, "65 chars", SyncRow(digest: String(repeating: "a", count: 65)))
        assertRejected(fixtures, "empty", SyncRow(digest: ""))
    }

    /// 件数と最終番号が負の値なら拒否されます。
    ///
    /// 責務: サンプル件数・事象件数・最終 sequence・最終 ordinal の負の値が CHECK で拒否されることを確認します。
    func testNegativeCountsAndNumbersAreRejected() throws {
        let fixtures = try makeFixtures()

        assertRejected(fixtures, "negative sampleCount", SyncRow(sampleCount: -1, lastSample: nil))
        assertRejected(fixtures, "negative eventCount", SyncRow(eventCount: -1, lastEvent: nil))
        assertRejected(fixtures, "negative lastSample", SyncRow(lastSample: -1))
        assertRejected(fixtures, "negative lastEvent", SyncRow(lastEvent: -1))
    }

    /// 件数と最終番号の組が食い違う行は拒否されます。
    ///
    /// 責務: 件数 0 なのに番号がある行、件数があるのに番号が無い行を、サンプル側・事象側とも拒否することを確認します。
    func testCountAndLastNumberPairMismatchIsRejected() throws {
        let fixtures = try makeFixtures()

        assertRejected(fixtures, "no samples but last sequence", SyncRow(sampleCount: 0, lastSample: 0))
        assertRejected(fixtures, "samples but no last sequence", SyncRow(sampleCount: 2, lastSample: nil))
        assertRejected(fixtures, "no events but last ordinal", SyncRow(eventCount: 0, lastEvent: 0))
        assertRejected(fixtures, "events but no last ordinal", SyncRow(eventCount: 1, lastEvent: nil))
    }

    /// サンプルも事象も 0 件の行は拒否されます。
    ///
    /// 責務: 件数の合計が 0 の行が CHECK で拒否されることを確認します。
    func testZeroTotalCountIsRejected() throws {
        let fixtures = try makeFixtures()

        assertRejected(fixtures, "empty track", SyncRow(sampleCount: 0, lastSample: nil, eventCount: 0, lastEvent: nil))
    }

    /// 存在しないセッションを参照する行は拒否され、同じセッションの2行目は主キー違反です。
    ///
    /// 責務: 外部キー違反と主キー重複が、それぞれ期待した拡張結果コードで拒否されることを確認します。
    func testForeignKeyAndPrimaryKeyViolationsAreRejected() throws {
        let fixtures = try makeFixtures()

        assertRejected(fixtures, "missing parent", code: .SQLITE_CONSTRAINT_FOREIGNKEY, SyncRow(session: SegmentationSchemaFixtures.sessionB))
        try fixtures.queue.write { try insert($0, SyncRow()) }
        assertRejected(fixtures, "duplicate key", code: .SQLITE_CONSTRAINT_PRIMARYKEY, SyncRow())
    }

    /// 親セッションを削除すると、同期記録の行も消えます。
    ///
    /// 責務: ON DELETE CASCADE の実際の動作を確認します。
    func testDeletingParentSessionDeletesSyncRow() throws {
        let fixtures = try makeFixtures()
        try fixtures.queue.write { try insert($0, SyncRow()) }

        try fixtures.queue.write {
            try $0.execute(sql: "DELETE FROM connection_sessions WHERE id = ?", arguments: [SegmentationSchemaFixtures.sessionA])
        }

        XCTAssertEqual(try fixtures.queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM connection_session_location_track_sync_states") }, 0)
    }
}

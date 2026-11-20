import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 位置表・事象表のCHECK・主キー・外部キーを直接INSERTで検証します。
///
/// SQLは固定リテラルと引数バインドだけで組み立てます。
final class ProjectZD8DatabaseMigratorLocationConstraintTests: XCTestCase {
    /// 位置行の既定値です。各テストは1項目だけ差し替えます。
    private struct SampleRow {
        var session = SegmentationSchemaFixtures.sessionA
        var sequence: Int64 = 0
        var monotonic: Int64 = 10
        var latitude: Double = 35
        var longitude: Double = 139
        var altitude: Double? = 10
        var horizontal: Double = 5
        var vertical: Double? = 3
        var speed: Double? = 1
        var course: Double? = 90
    }

    /// 全Migration適用済みで親セッションを1件持つ組立てを返します。
    ///
    /// 責務: 位置・事象の外部キー参照先となるセッション `sessionA` を用意します。
    /// - Throws: DB作成またはセッション挿入の失敗。
    private func makeFixtures() throws -> SegmentationSchemaFixtures {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { try fixtures.insertSession($0) }
        return fixtures
    }

    /// 位置行を直接挿入します。
    ///
    /// 責務: 1件の `connection_session_location_samples` 行を引数バインドで追加します。
    /// - Parameters:
    ///   - database: 書込み中の接続。
    ///   - row: 挿入する値。
    /// - Throws: SQLite書込み失敗(制約違反を含む)。
    private func insert(_ database: Database, _ row: SampleRow) throws {
        let values: [(any DatabaseValueConvertible)?] = [
            row.session, row.sequence, 1_000_000, row.monotonic, row.latitude, row.longitude,
            row.altitude, row.horizontal, row.vertical, row.speed, row.course
        ]
        try database.execute(
            sql: """
                INSERT INTO connection_session_location_samples
                (sessionID, sequence, observedAtMicroseconds, monotonicNanoseconds, latitude, longitude,
                 altitudeMeters, horizontalAccuracyMeters, verticalAccuracyMeters, speedMetersPerSecond, courseDegrees)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: StatementArguments(values)
        )
    }

    /// 事象行を直接挿入します。
    ///
    /// 責務: 1件の `connection_session_location_events` 行を引数バインドで追加します。
    /// - Parameters:
    ///   - database: 書込み中の接続。
    ///   - session: 親セッションID。
    ///   - ordinal: 事象番号。
    ///   - kind: 種類の保存値。
    /// - Throws: SQLite書込み失敗(制約違反を含む)。
    private func insertEvent(
        _ database: Database,
        session: String = SegmentationSchemaFixtures.sessionA,
        ordinal: Int64 = 0,
        kind: String = "recording"
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO connection_session_location_events (sessionID, eventOrdinal, occurredAtMicroseconds, kind)
                VALUES (?, ?, 1000000, ?)
                """,
            arguments: [session, ordinal, kind]
        )
    }

    /// 書込みが指定の拡張結果コードで拒否されることを検証します。
    ///
    /// 責務: 成功や別種のエラーでなく、期待した種類の制約違反で失敗したことを確認します。
    /// - Parameters:
    ///   - fixtures: 検証用の組立て。
    ///   - code: 期待する拡張結果コード。
    ///   - label: 失敗時に添える説明。
    ///   - body: 拒否されるべき書込み。
    private func assertRejected(
        _ fixtures: SegmentationSchemaFixtures,
        _ label: String,
        code: ResultCode = .SQLITE_CONSTRAINT_CHECK,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: (Database) throws -> Void
    ) {
        XCTAssertThrowsError(try fixtures.queue.write(body), label, file: file, line: line) { error in
            XCTAssertEqual((error as? DatabaseError)?.extendedResultCode, code, "\(label): \(error)", file: file, line: line)
        }
    }

    /// 既定値の位置行と事象行は挿入できます。
    ///
    /// 責務: 以降の拒否テストの対照として、既定行が制約を満たすことを確認します。
    func testDefaultRowsAreAccepted() throws {
        let fixtures = try makeFixtures()

        try fixtures.queue.write {
            try insert($0, SampleRow())
            try insertEvent($0)
        }

        XCTAssertEqual(try fixtures.queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM connection_session_location_samples") }, 1)
        XCTAssertEqual(try fixtures.queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM connection_session_location_events") }, 1)
    }

    /// 境界値(緯度±90・経度±180・進行方向0・水平精度0)は受け入れられます。
    ///
    /// 責務: 範囲の端の値がCHECKで拒否されないことを確認します。
    func testBoundaryValuesAreAccepted() throws {
        let fixtures = try makeFixtures()
        var rows: [SampleRow] = []
        rows.append(SampleRow(sequence: 0, latitude: 90, longitude: 180))
        rows.append(SampleRow(sequence: 1, latitude: -90, longitude: -180))
        rows.append(SampleRow(sequence: 2, horizontal: 0, course: 0))
        rows.append(SampleRow(sequence: 3, altitude: -50, vertical: 0, speed: 0, course: 359.999))

        try fixtures.queue.write { database in
            for row in rows {
                try insert(database, row)
            }
        }

        XCTAssertEqual(try fixtures.queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM connection_session_location_samples") }, 4)
    }

    /// 緯度が -90...90 の外なら拒否されます。
    ///
    /// 責務: 上側・下側の範囲外の緯度がCHECKで拒否されることを確認します。
    func testLatitudeOutOfRangeIsRejected() throws {
        let fixtures = try makeFixtures()

        assertRejected(fixtures, "緯度 90 超") { try insert($0, SampleRow(latitude: 90.0001)) }
        assertRejected(fixtures, "緯度 -90 未満") { try insert($0, SampleRow(latitude: -90.0001)) }
    }

    /// 経度が -180...180 の外なら拒否されます。
    ///
    /// 責務: 上側・下側の範囲外の経度がCHECKで拒否されることを確認します。
    func testLongitudeOutOfRangeIsRejected() throws {
        let fixtures = try makeFixtures()

        assertRejected(fixtures, "経度 180 超") { try insert($0, SampleRow(longitude: 180.0001)) }
        assertRejected(fixtures, "経度 -180 未満") { try insert($0, SampleRow(longitude: -180.0001)) }
    }

    /// 精度・速度・進行方向・時計の範囲外は拒否されます。
    ///
    /// 責務: 水平精度・垂直精度・速度が負、進行方向が負または360以上、単調時刻が負の行を確認します。
    func testNegativeOrOutOfRangeMeasurementsAreRejected() throws {
        let fixtures = try makeFixtures()

        assertRejected(fixtures, "水平精度が負") { try insert($0, SampleRow(horizontal: -0.5)) }
        assertRejected(fixtures, "垂直精度が負") { try insert($0, SampleRow(vertical: -0.5)) }
        assertRejected(fixtures, "速度が負") { try insert($0, SampleRow(speed: -0.5)) }
        assertRejected(fixtures, "進行方向が負") { try insert($0, SampleRow(course: -0.5)) }
        assertRejected(fixtures, "進行方向が360") { try insert($0, SampleRow(course: 360)) }
        assertRejected(fixtures, "進行方向が360超") { try insert($0, SampleRow(course: 400)) }
        assertRejected(fixtures, "単調時刻が負") { try insert($0, SampleRow(monotonic: -1)) }
    }

    /// sequence が負なら拒否されます。
    ///
    /// 責務: 負の記録順序がCHECKで拒否されることを確認します。
    func testNegativeSequenceIsRejected() throws {
        let fixtures = try makeFixtures()

        assertRejected(fixtures, "sequence が負") { try insert($0, SampleRow(sequence: -1)) }
    }

    /// 標高と垂直精度は、どちらも値ありかどちらも NULL でなければ拒否されます。
    ///
    /// 責務: 標高だけ値あり・垂直精度だけ値ありの行が拒否され、両方 NULL の行は受け入れられることを確認します。
    func testAltitudeAndVerticalAccuracyMustBeSetTogether() throws {
        let fixtures = try makeFixtures()

        assertRejected(fixtures, "標高だけ値あり") { try insert($0, SampleRow(altitude: 10, vertical: nil)) }
        assertRejected(fixtures, "垂直精度だけ値あり") { try insert($0, SampleRow(altitude: nil, vertical: 3)) }
        XCTAssertNoThrow(try fixtures.queue.write { try insert($0, SampleRow(altitude: nil, vertical: nil)) })
    }

    /// 同じ (sessionID, sequence) の位置は拒否され、別セッションの同じ sequence は受け入れられます。
    ///
    /// 責務: 位置表の主キーの境界を確認します。
    func testSamplePrimaryKeyIsSessionAndSequence() throws {
        let fixtures = try makeFixtures()
        try fixtures.queue.write {
            try fixtures.insertSession($0, id: SegmentationSchemaFixtures.sessionB)
            try insert($0, SampleRow())
        }

        assertRejected(fixtures, "位置の主キー重複", code: .SQLITE_CONSTRAINT_PRIMARYKEY) { try insert($0, SampleRow()) }
        XCTAssertNoThrow(try fixtures.queue.write { try insert($0, SampleRow(session: SegmentationSchemaFixtures.sessionB)) })
    }

    /// 存在しないセッションIDの行は外部キーで拒否されます。
    ///
    /// 責務: 位置行・事象行の両方で、親セッション不在が外部キー違反になることを確認します。
    func testRowsWithoutParentSessionAreRejectedByForeignKey() throws {
        let fixtures = try makeFixtures()
        let missing = SegmentationSchemaFixtures.sessionB

        assertRejected(fixtures, "位置の外部キー", code: .SQLITE_CONSTRAINT_FOREIGNKEY) { try insert($0, SampleRow(session: missing)) }
        assertRejected(fixtures, "事象の外部キー", code: .SQLITE_CONSTRAINT_FOREIGNKEY) { try insertEvent($0, session: missing) }
    }

    /// 事象の kind が未知の文字列なら拒否され、9種類の保存値は受け入れられます。
    ///
    /// 責務: kind のCHECKが `ConnectionSessionLocationEventKind` の全 rawValue を許可し、他を拒否することを確認します。
    func testEventKindMustBeKnown() throws {
        let fixtures = try makeFixtures()

        assertRejected(fixtures, "未知の kind") { try insertEvent($0, kind: "unknownKind") }
        assertRejected(fixtures, "空の kind") { try insertEvent($0, kind: "") }
        try fixtures.queue.write { database in
            for (index, kind) in ConnectionSessionLocationEventKind.allCases.enumerated() {
                try insertEvent(database, ordinal: Int64(index), kind: kind.rawValue)
            }
        }
        XCTAssertEqual(try fixtures.queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM connection_session_location_events") }, 9)
    }

    /// eventOrdinal が負なら拒否され、同じ (sessionID, eventOrdinal) は主キーで拒否されます。
    ///
    /// 責務: 事象表の番号のCHECKと主キーを確認します。
    func testEventOrdinalAndPrimaryKey() throws {
        let fixtures = try makeFixtures()
        try fixtures.queue.write { try insertEvent($0) }

        assertRejected(fixtures, "eventOrdinal が負") { try insertEvent($0, ordinal: -1) }
        assertRejected(fixtures, "事象の主キー重複", code: .SQLITE_CONSTRAINT_PRIMARYKEY) { try insertEvent($0) }
    }
}

import GRDB
import XCTest
@testable import ProjectZD8

/// PID専用テーブルのMigration、改訂、制約、復元を検証します。
final class GRDBOBDPIDDefinitionRepositoryTests: XCTestCase {
    /// 初期Migrationと標準seedを取得可能にします。
    ///
    /// 責務: 空DBへPIDテーブルと確認済み2定義が作成されることを確認します。
    func testMigratesAndInstallsVerifiedDefinitions() throws {
        let queue = try DatabaseQueue()
        let repository = try GRDBOBDPIDDefinitionRepository(databaseQueue: queue)
        try StandardOBDPIDSeed.install(into: repository)

        XCTAssertEqual(try repository.definition(service: 1, pid: 5), StandardOBDPIDSeed.definitions[0])
        XCTAssertEqual(try repository.definition(service: 1, pid: 12), StandardOBDPIDSeed.definitions[1])
    }

    /// 新しい改訂だけが既存定義を更新できます。
    ///
    /// 責務: 同一Service/PIDの改訂後退を拒否し改訂増加だけを反映することを確認します。
    func testUpsertNeverRegressesRevision() throws {
        let repository = try GRDBOBDPIDDefinitionRepository(databaseQueue: DatabaseQueue())
        try repository.upsert(makeDefinition(formula: "A", revision: 2))
        try repository.upsert(makeDefinition(formula: "A + 1", revision: 1))
        XCTAssertEqual(try repository.definition(service: 1, pid: 5)?.formula, "A")

        try repository.upsert(makeDefinition(formula: "A - 40", revision: 3))
        XCTAssertEqual(try repository.definition(service: 1, pid: 5)?.revision, 3)
        XCTAssertEqual(try repository.definition(service: 1, pid: 5)?.formula, "A - 40")
    }

    /// 最小最大値の組が完全で順序も正しい場合だけ保存します。
    ///
    /// 責務: NULL/NULLと正順範囲だけを許可し、片側NULLと逆転範囲をCHECK制約が拒否することを確認します。
    func testRangeConstraintHandlesNullAndPairedValues() throws {
        let queue = try DatabaseQueue()
        _ = try GRDBOBDPIDDefinitionRepository(databaseQueue: queue)
        try queue.write { database in
            try insertDirect(database, minimum: nil, maximum: nil, pid: 1)
            try insertDirect(database, minimum: -40, maximum: 215, pid: 2)
            XCTAssertThrowsError(try insertDirect(database, minimum: nil, maximum: 10, pid: 3))
            XCTAssertThrowsError(try insertDirect(database, minimum: -40, maximum: nil, pid: 4))
            XCTAssertThrowsError(try insertDirect(database, minimum: 10, maximum: 0, pid: 5))
        }
    }

    /// Service/PID範囲と必要バイト数の不正値を拒否します。
    ///
    /// 責務: SQL直接書込みでも識別子とバイト数制約を迂回できないことを確認します。
    func testIdentifierAndByteCountConstraintsRejectDirectSQLBypass() throws {
        let queue = try DatabaseQueue()
        _ = try GRDBOBDPIDDefinitionRepository(databaseQueue: queue)
        try queue.write { database in
            XCTAssertThrowsError(try database.execute(sql: "INSERT INTO obd_pid_definitions VALUES (256, 1, 'x', 1, 'A', '', NULL, NULL, 's', 1)"))
            XCTAssertThrowsError(try database.execute(sql: "INSERT INTO obd_pid_definitions VALUES (1, 1, 'x', 0, 'A', '', NULL, NULL, 's', 1)"))
        }
    }

    /// 改訂テスト用のPID定義を生成します。
    ///
    /// 責務: 数式と改訂だけが異なる同一PID定義を提供します。
    /// - Parameters:
    ///   - formula: 保存する式。
    ///   - revision: 保存する改訂。
    /// - Returns: Service 01 PID 05の定義。
    private func makeDefinition(formula: String, revision: Int) -> OBDPIDDefinition {
        OBDPIDDefinition(service: 1, pid: 5, nameKey: "test", requiredByteCount: 1, formula: formula, unit: "u", minimumValue: nil, maximumValue: nil, sourceURI: "test://source", revision: revision)
    }

    /// 制約検証用レコードをSQLへ直接挿入します。
    ///
    /// 責務: 最小最大値の組だけを変えた有効形式レコードをDB制約へ渡します。
    /// - Parameters:
    ///   - database: 書込み中のDB接続。
    ///   - minimum: 最小値列。
    ///   - maximum: 最大値列。
    ///   - pid: レコードを区別するPID。
    /// - Throws: DB制約に違反した場合のGRDBエラー。
    private func insertDirect(_ database: Database, minimum: Double?, maximum: Double?, pid: Int) throws {
        try database.execute(
            sql: "INSERT INTO obd_pid_definitions VALUES (1, ?, 'x', 1, 'A', '', ?, ?, 's', 1)",
            arguments: [pid, minimum, maximum]
        )
    }
}

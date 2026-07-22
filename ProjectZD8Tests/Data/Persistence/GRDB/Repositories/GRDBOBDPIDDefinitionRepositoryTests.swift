import GRDB
import XCTest
@testable import ProjectZD8

/// PID専用テーブルのMigration、改訂、制約、復元を検証します。
@MainActor
final class GRDBOBDPIDDefinitionRepositoryTests: XCTestCase {
    /// 初期Migrationと掲載167件の標準seedを取得可能にします。
    ///
    /// 責務: 空DBへPIDテーブルと現在の確認済み定義が作成されることを確認します。
    func testMigratesAndInstallsVerifiedDefinitions() throws {
        let queue = try DatabaseQueue()
        let repository = try GRDBOBDPIDDefinitionRepository(databaseQueue: queue)
        try StandardOBDPIDSeed.install(into: repository)

        XCTAssertEqual(try repository.definitions(), StandardOBDPIDSeed.definitions)
        XCTAssertEqual(try repository.definitions().count, 167)
    }

    /// Service 01 PID A6を規格の4バイト走行距離定義として登録します。
    ///
    /// 責務: 走行距離PIDの識別子、変換式、単位、範囲、出典を永続化後に確認します。
    func testInstallsStandardOdometerDefinition() throws {
        let repository = try GRDBOBDPIDDefinitionRepository(databaseQueue: DatabaseQueue())
        try StandardOBDPIDSeed.install(into: repository)

        let definition = try XCTUnwrap(repository.definition(service: 0x01, pid: 0xA6))
        XCTAssertEqual(definition.nameKey, "obd.pid.01.A6.name")
        XCTAssertEqual(definition.requiredByteCount, 4)
        XCTAssertEqual(definition.formula, "(A * 16777216 + B * 65536 + C * 256 + D) / 10")
        XCTAssertEqual(definition.unit, "km")
        XCTAssertEqual(definition.minimumValue, 0)
        XCTAssertEqual(definition.maximumValue, 429_496_729.5)
        XCTAssertEqual(definition.sourceURI, "https://www.csselectronics.com/pages/obd2-pid-table-on-board-diagnostics-j1979")
    }

    /// ZD8専用定義をヘッダーおよび型式スコープとともに登録します。
    ///
    /// 責務: 確定済みの走行距離とAT油温だけがZD8専用定義として永続化されることを確認します。
    func testInstallsOnlyConfirmedZD8DefinitionsWithVehicleScope() throws {
        let repository = try GRDBOBDPIDDefinitionRepository(databaseQueue: DatabaseQueue())

        try ZD8OBDPIDSeed.install(into: repository)

        let definitions = try repository.definitions()
        XCTAssertEqual(definitions, ZD8OBDPIDSeed.definitions)
        XCTAssertEqual(definitions.map(\.header), [0x7E0, 0x7E1])
        XCTAssertEqual(definitions.map(\.vehicleModelCode), ["ZD8", "ZD8"])
        XCTAssertEqual(definitions.map(\.pid), [0x02, 0x17])
    }

    /// ヘッダーと型式の片方だけを持つ専用PIDを拒否します。
    ///
    /// 責務: SQL直接書込みでも車種専用PIDの適用範囲を部分登録できないことを確認します。
    func testVehicleSpecificScopeRequiresHeaderAndModelCodeTogether() throws {
        let queue = try DatabaseQueue()
        _ = try GRDBOBDPIDDefinitionRepository(databaseQueue: queue)

        try queue.write { database in
            XCTAssertThrowsError(try insertVehicleScopeDirect(database, header: 0x7E0, modelCode: nil, pid: 0x02))
            XCTAssertThrowsError(try insertVehicleScopeDirect(database, header: nil, modelCode: "ZD8", pid: 0x17))
        }
    }

    /// 登録順に依存せずService/PID順の一覧を取得します。
    ///
    /// 責務: GRDB一覧読込が全PID定義を安定した識別子順で復元することを確認します。
    func testDefinitionsReturnsAllRecordsInServiceAndPIDOrder() throws {
        let repository = try GRDBOBDPIDDefinitionRepository(databaseQueue: DatabaseQueue())
        for definition in StandardOBDPIDSeed.definitions.reversed() {
            try repository.upsert(definition)
        }

        XCTAssertEqual(try repository.definitions(), StandardOBDPIDSeed.definitions)
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
            XCTAssertThrowsError(try insertRaw(database, service: 256, byteCount: 1))
            XCTAssertThrowsError(try insertRaw(database, service: 1, byteCount: 0))
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
            sql: """
                INSERT INTO obd_pid_definitions
                    (service, pid, nameKey, requiredByteCount, formula, unit, minimumValue, maximumValue,
                     sourceURI, revision, summaryKey, highValueKey, lowValueKey, correlationKey)
                VALUES (1, ?, 'x', 1, 'A', '', ?, ?, 's', 1, 's', 'h', 'l', 'c')
                """,
            arguments: [pid, minimum, maximum]
        )
    }

    /// 識別子またはバイト数だけを変えた直接SQLレコードを挿入します。
    ///
    /// 責務: 1件の不正候補を現行14列スキーマのCHECK制約へ渡します。
    /// - Parameters:
    ///   - database: 書込み中のDB接続。
    ///   - service: 検証するService値。
    ///   - byteCount: 検証する必要バイト数。
    /// - Throws: DB制約に違反した場合のGRDBエラー。
    private func insertRaw(_ database: Database, service: Int, byteCount: Int) throws {
        try database.execute(
            sql: """
                INSERT INTO obd_pid_definitions
                    (service, pid, nameKey, requiredByteCount, formula, unit, minimumValue, maximumValue,
                     sourceURI, revision, summaryKey, highValueKey, lowValueKey, correlationKey)
                VALUES (?, 1, 'x', ?, 'A', '', NULL, NULL, 's', 1, 's', 'h', 'l', 'c')
                """,
            arguments: [service, byteCount]
        )
    }

    /// 車種専用スコープ列を指定してSQLへ直接挿入します。
    ///
    /// 責務: ヘッダーと型式の組合せを車種専用制約へ渡します。
    /// - Parameters:
    ///   - database: 書込み中のDB接続。
    ///   - header: ECU送信ヘッダー。
    ///   - modelCode: 適用型式。
    ///   - pid: レコードを区別するPID。
    /// - Throws: DB制約に違反した場合のGRDBエラー。
    private func insertVehicleScopeDirect(_ database: Database, header: Int?, modelCode: String?, pid: Int) throws {
        try database.execute(
            sql: """
                INSERT INTO obd_pid_definitions
                    (service, pid, nameKey, requiredByteCount, formula, unit, minimumValue, maximumValue,
                     sourceURI, revision, summaryKey, highValueKey, lowValueKey, correlationKey, header, vehicleModelCode)
                VALUES (33, ?, 'x', 1, 'A', '', NULL, NULL, 's', 1, 's', 'h', 'l', 'c', ?, ?)
                """,
            arguments: [pid, header, modelCode]
        )
    }
}

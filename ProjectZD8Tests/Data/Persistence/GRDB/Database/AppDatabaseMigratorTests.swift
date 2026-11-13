import GRDB
import XCTest
@testable import ProjectZD8

/// 初版スキーマの構造と追記専用の規則を検証します。
final class AppDatabaseMigratorTests: XCTestCase {
    /// 責務: 現行スキーマが想定テーブルを全て作成することを確認します。
    func testMigrationCreatesAllTables() throws {
        let database = try AppDatabaseTesting.makeDatabase()
        let tables = try database.writer.read { db in
            try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'grdb_%' AND name NOT LIKE 'sqlite_%'")
        }
        XCTAssertEqual(tables, [
            "vehicles", "photos", "vehicle_pid_settings", "maintenance_records",
            "sessions", "session_pids", "session_samples", "sync_records", "sync_state"
        ])
    }

    /// 責務: Rawサンプルを更新できないことを確認します。
    func testSessionSamplesRejectUpdate() throws {
        let database = try AppDatabaseTesting.makeDatabase()
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO vehicles (id, vin, name, manufacturer, engineModel, powertrain, energySources, note, createdAt, modifiedAt) VALUES ('v', '', 'n', '', '', 'combustion', '[]', '', 0, 0)")
            try db.execute(sql: "INSERT INTO sessions (id, vehicleID, startedAt, isDemo, adapterName, adapterTransport, platform, deviceID, deviceName, appVersion, appBuild, pollingPolicyVersion, rawAvailability, modifiedAt) VALUES ('s', 'v', 0, 0, 'a', 'demo', 'mac', 'd', 'd', '1', '1', 1, 'local', 0)")
            try db.execute(sql: "INSERT INTO session_samples (sessionID, sequence, tick, elapsedMicroseconds, service, pid, outcome, payload) VALUES ('s', 0, 0, 0, 1, 12, 0, x'0000')")
        }
        XCTAssertThrowsError(try database.writer.write { db in
            try db.execute(sql: "UPDATE session_samples SET outcome = 1")
        })
    }
}

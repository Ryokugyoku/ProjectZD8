import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `release_v1_add_connection_session_location_samples_and_events` の表・列の作成と、旧スキーマからの移行を検証します。
final class ProjectZD8DatabaseMigratorLocationTests: XCTestCase {
    /// 位置のMigrationの直前に登録されている識別子です。
    private static let previousMigration = "release_v1_add_connection_session_acquisition_adapter_probe"
    /// 位置のMigration識別子です。
    private static let locationMigration = "release_v1_add_connection_session_location_samples_and_events"

    /// 位置表に期待する列名です。
    private static let sampleColumns: Set<String> = [
        "sessionID", "sequence", "observedAtMicroseconds", "monotonicNanoseconds", "latitude", "longitude",
        "altitudeMeters", "horizontalAccuracyMeters", "verticalAccuracyMeters", "speedMetersPerSecond", "courseDegrees"
    ]
    /// 位置表のうちNULLを許す列名です。
    private static let nullableSampleColumns: Set<String> = [
        "altitudeMeters", "verticalAccuracyMeters", "speedMetersPerSecond", "courseDegrees"
    ]
    /// 事象表に期待する列名です。
    private static let eventColumns: Set<String> = ["sessionID", "eventOrdinal", "occurredAtMicroseconds", "kind"]

    /// 全Migrationを適用すると、2つの表が期待する列と主キーで作成されます。
    ///
    /// 責務: 位置表・事象表の存在、列名の集合、NULL許容、主キー、行が空であることを確認します。
    func testFullMigrationCreatesLocationTablesWithExpectedColumns() throws {
        let queue = try DatabaseQueue()

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        try queue.read { database in
            XCTAssertTrue(try database.tableExists("connection_session_location_samples"))
            XCTAssertTrue(try database.tableExists("connection_session_location_events"))
            let samples = try database.columns(in: "connection_session_location_samples")
            XCTAssertEqual(Set(samples.map(\.name)), Self.sampleColumns)
            let nullable = Set(samples.filter { !$0.isNotNull }.map(\.name))
            XCTAssertEqual(nullable, Self.nullableSampleColumns)
            XCTAssertEqual(try database.primaryKey("connection_session_location_samples").columns, ["sessionID", "sequence"])
            let events = try database.columns(in: "connection_session_location_events")
            XCTAssertEqual(Set(events.map(\.name)), Self.eventColumns)
            XCTAssertTrue(events.allSatisfy(\.isNotNull))
            XCTAssertEqual(try database.primaryKey("connection_session_location_events").columns, ["sessionID", "eventOrdinal"])
            XCTAssertEqual(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM connection_session_location_samples"), 0)
            XCTAssertEqual(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM connection_session_location_events"), 0)
        }
    }

    /// 直前のMigrationまででは位置の表が存在せず、位置のMigrationが最後まで未適用です。
    ///
    /// 責務: 「適用前後の比較」が空振りしないよう、直前時点の状態が位置の表を含まないことを確認します。
    func testPreviousMigrationStateHasNoLocationTables() throws {
        let queue = try DatabaseQueue()

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue, upTo: Self.previousMigration)

        try queue.read { database in
            XCTAssertFalse(try database.tableExists("connection_session_location_samples"))
            XCTAssertFalse(try database.tableExists("connection_session_location_events"))
        }
        let applied = try queue.read { try ProjectZD8DatabaseMigrator.migrator.appliedIdentifiers($0) }
        XCTAssertFalse(applied.contains(Self.locationMigration))
    }

    /// 位置のMigrationは直前のMigrationの直後に登録されています。
    ///
    /// 責務: 全適用後の識別子の並びで、位置のMigrationが直前の識別子の次にあることを確認します。
    func testLocationMigrationIsRegisteredRightAfterPreviousMigration() throws {
        let queue = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        let applied = try queue.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid") }

        let previousIndex = try XCTUnwrap(applied.firstIndex(of: Self.previousMigration))
        XCTAssertEqual(applied.dropFirst(previousIndex + 1).first, Self.locationMigration)
    }

    /// 直前まで適用済みのDBを最新へ移行しても、既存のセッション行は変わらず、位置を追記できます。
    ///
    /// 責務: 旧スキーマで保存したセッション行の全列保持と、移行後の位置・事象の追記と読出しを確認します。
    func testUpgradePreservesExistingSessionAndAcceptsLocations() throws {
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

        let after = try queue.read { try Row.fetchAll($0, sql: "SELECT * FROM connection_sessions") }
        XCTAssertEqual(after, before)
        let sessionID = ConnectionSessionID(rawValue: try XCTUnwrap(UUID(uuidString: SegmentationSchemaFixtures.sessionA)))
        let repository = try GRDBConnectionSessionLocationRepository(databaseQueue: queue)
        let fix = try GRDBConnectionSessionLocationFixtures.fix()
        try repository.appendSample(fix, for: sessionID)
        try repository.appendEvent(.recording, occurredAt: Date(timeIntervalSince1970: 95), for: sessionID)
        XCTAssertEqual(try repository.samples(for: sessionID), [ConnectionSessionLocationSample(sequence: 0, fix: fix)])
        XCTAssertEqual(try repository.events(for: sessionID).map(\.kind), [.recording])
    }
}

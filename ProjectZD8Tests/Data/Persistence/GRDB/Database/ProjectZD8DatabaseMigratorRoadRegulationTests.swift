import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `release_v1_add_road_regulation_datasets` の表・索引・外部キーの構造と、直前の Migration からの移行を検証します。
///
/// SQL は固定リテラルと引数バインドだけで組み立てます。
@MainActor
final class ProjectZD8DatabaseMigratorRoadRegulationTests: XCTestCase {
    private static let previousMigration = "release_v1_add_connection_session_location_track_sync_states"
    private static let migration = "release_v1_add_road_regulation_datasets"
    private static let tables = ["road_regulation_datasets", "road_regulation_dataset_rejections", "road_regulations", "road_regulation_cells"]

    /// 全 Migration を適用すると、4つの表が期待する列・NOT NULL・主キーで作成されます。
    ///
    /// 責務: 表ごとの列名の集合、NULL を許す列、主キーを確認します。
    func testFullMigrationCreatesTablesWithExpectedColumns() throws {
        let queue = try DatabaseQueue()

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        try queue.read { database in
            let datasetColumns = try database.columns(in: "road_regulation_datasets")
            XCTAssertEqual(Set(datasetColumns.map(\.name)), [
                "id", "prefectureCode", "state", "publicationStamp", "sourceURL", "downloadedAtMicroseconds", "activatedAtMicroseconds",
                "dataYear", "dataMonth", "formatVersion", "totalRowCount", "importedCount", "skippedOutOfScopeCount",
                "skippedAbolishedCount", "coverageMinLatitude", "coverageMaxLatitude", "coverageMinLongitude", "coverageMaxLongitude"
            ])
            XCTAssertEqual(Set(datasetColumns.filter { !$0.isNotNull }.map(\.name)), [
                "activatedAtMicroseconds", "dataYear", "dataMonth", "formatVersion",
                "coverageMinLatitude", "coverageMaxLatitude", "coverageMinLongitude", "coverageMaxLongitude"
            ])
            XCTAssertEqual(try database.primaryKey("road_regulation_datasets").columns, ["id"])
            XCTAssertEqual(Set(try database.columns(in: "road_regulation_dataset_rejections").map(\.name)), ["datasetID", "reason", "count"])
            XCTAssertEqual(try database.primaryKey("road_regulation_dataset_rejections").columns, ["datasetID", "reason"])
            XCTAssertEqual(try database.primaryKey("road_regulation_cells").columns, ["datasetID", "cellKey", "regulationID"])
            XCTAssertEqual(try database.primaryKey("road_regulations").columns, ["id"])
        }
    }

    /// 規制の表の列と NULL 許容を確認します。
    ///
    /// 責務: 列名の集合と、NULL を許す列(速度・片側・並び・外周・条件)を確認します。
    func testRegulationTableColumns() throws {
        let queue = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        try queue.read { database in
            let columns = try database.columns(in: "road_regulations")
            XCTAssertEqual(Set(columns.map(\.name)), [
                "id", "datasetID", "uniqueKey", "kind", "speedLimitKph", "sideCode", "oneWayOrder", "perimeterRoadIncluded", "conditions", "geometry"
            ])
            XCTAssertEqual(
                Set(columns.filter { !$0.isNotNull }.map(\.name)),
                ["id", "speedLimitKph", "sideCode", "oneWayOrder", "perimeterRoadIncluded", "conditions"]
            )
            XCTAssertEqual(columns.first { $0.name == "geometry" }?.type.uppercased(), "BLOB")
        }
    }

    /// 同じ県の active・importing は部分一意索引で1つに制限されます。
    ///
    /// 責務: 2つの索引が一意で部分索引であることを、定義の問い合わせで確認します。
    func testPartialUniqueIndexesExist() throws {
        let queue = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        let rows = try queue.read { try Row.fetchAll($0, sql: "SELECT name, \"unique\", partial FROM pragma_index_list('road_regulation_datasets')") }

        for name in ["road_regulation_datasets_one_active", "road_regulation_datasets_one_importing"] {
            let row = try XCTUnwrap(rows.first { ($0["name"] as String) == name }, name)
            XCTAssertEqual(row["unique"] as Int, 1)
            XCTAssertEqual(row["partial"] as Int, 1)
        }
    }

    /// 子の表の外部キーはすべて版へ向かい、削除は CASCADE です。升目の表は規制へ外部キーを持ちません。
    ///
    /// 責務: 3つの子の表の外部キーの数・参照先・ON DELETE を、定義の問い合わせで確認します。
    func testForeignKeysReferenceDatasetsWithCascadeAndCellsHaveNoRegulationKey() throws {
        let queue = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        for table in ["road_regulation_dataset_rejections", "road_regulations", "road_regulation_cells"] {
            let rows = try queue.read {
                try Row.fetchAll($0, sql: "SELECT \"table\", \"from\", on_delete FROM pragma_foreign_key_list(?)", arguments: [table])
            }
            XCTAssertEqual(rows.count, 1, table)
            XCTAssertEqual(rows.first?["table"] as String?, "road_regulation_datasets", table)
            XCTAssertEqual(rows.first?["from"] as String?, "datasetID", table)
            XCTAssertEqual(rows.first?["on_delete"] as String?, "CASCADE", table)
        }
    }

    /// 直前の Migration までではこれらの表が無く、この Migration は直前の次に登録されています。
    ///
    /// 責務: 直前時点の状態と、全適用後の識別子の並びを確認します。
    func testPreviousStateHasNoTablesAndMigrationIsRegisteredRightAfter() throws {
        let previous = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(previous, upTo: Self.previousMigration)
        for table in Self.tables {
            XCTAssertFalse(try previous.read { try $0.tableExists(table) }, table)
        }

        let full = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(full)
        let applied = try full.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid") }

        let previousIndex = try XCTUnwrap(applied.firstIndex(of: Self.previousMigration))
        XCTAssertEqual(applied.dropFirst(previousIndex + 1).first, Self.migration)
    }

    /// 直前まで適用済みの DB を最新へ移行しても、既存の行は変わらず、新しい表が使えます。
    ///
    /// 責務: 移行前後のセッション行の一致と、移行後の版・規制の保存を確認します。
    func testUpgradePreservesExistingRowsAndAcceptsRegulations() throws {
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
        let rows = RoadRegulationSchemaRows(queue: queue)
        try queue.write {
            try rows.insert($0, RoadRegulationSchemaRows.Dataset.active())
            try rows.insert($0, RoadRegulationSchemaRows.Regulation(id: 1))
        }
        XCTAssertEqual(try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM road_regulations") }, 1)
    }

    /// 全 Migration を再度適用しても、保存済みの規制は変わりません。
    ///
    /// 責務: 適用済みの DB への再適用が行を保つことを確認します。
    func testReapplyingMigrationsKeepsRows() throws {
        let rows = try RoadRegulationSchemaRows()
        try rows.queue.write {
            try rows.insert($0, RoadRegulationSchemaRows.Dataset.active())
            try rows.insert($0, RoadRegulationSchemaRows.Regulation(id: 1))
        }

        try ProjectZD8DatabaseMigrator.migrator.migrate(rows.queue)

        XCTAssertEqual(try rows.queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM road_regulations") }, 1)
        XCTAssertEqual(try rows.queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM road_regulation_datasets") }, 1)
    }
}

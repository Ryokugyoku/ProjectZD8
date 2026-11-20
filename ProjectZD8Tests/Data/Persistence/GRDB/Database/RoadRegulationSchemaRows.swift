import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 交通規制の表の制約テストが共有する、全 Migration 適用済み DB と、固定 SQL・引数バインドだけの直接 INSERT の部品です。
struct RoadRegulationSchemaRows {
    /// 版の行の既定値です。既定は制約を満たす importing の行で、各テストは必要な項目だけ差し替えます。
    struct Dataset {
        var id = "00000000-0000-0000-0000-0000000000a1"
        var prefecture: Int64 = 47
        var state = "importing"
        var stamp = "202611010000"
        var activatedAt: Int64?
        var dataYear: Int64?
        var dataMonth: Int64?
        var formatVersion: String?
        var coverage: [Double?] = [nil, nil, nil, nil]
        var totalRows: Int64 = 0
        var importedCount: Int64 = 0
        var skippedOutOfScope: Int64 = 0
        var skippedAbolished: Int64 = 0

        /// active に必要な欄をすべて埋めた行を返します。
        static func active(id: String = "00000000-0000-0000-0000-0000000000a1", prefecture: Int64 = 47) -> Dataset {
            Dataset(id: id, prefecture: prefecture, state: "active", activatedAt: 5, dataYear: 2026, dataMonth: 9,
                    formatVersion: "2.1", coverage: [26.0, 26.5, 127.5, 128.0])
        }
    }

    /// 規制の行の既定値です。既定は制約を満たす速度の区間の行です。
    struct Regulation {
        var id: Int64?
        var dataset = "00000000-0000-0000-0000-0000000000a1"
        var uniqueKey = "key-1"
        var kind = "speedLimitSection"
        var speed: Int64? = 40
        var side: Int64?
        var oneWay: Int64?
        var perimeter: Int64?
        var conditions: String?
        var geometry = Data([1, 0, 0])
    }

    /// 全 Migration 適用済みの DB Queue です。
    let queue: DatabaseQueue

    /// 全 Migration を適用した空 DB を作ります。
    ///
    /// 責務: テスト専用の DB を作り、外部キーが有効であることを前提として確認します。
    /// - Throws: DB 作成または Migration の失敗。
    init() throws {
        queue = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)
        XCTAssertEqual(try queue.read { try Int.fetchOne($0, sql: "PRAGMA foreign_keys") }, 1)
    }

    /// 既存の DB Queue を包みます。
    ///
    /// 責務: 移行テストが、自分で Migration した Queue に挿入の部品を使えるようにします。
    init(queue: DatabaseQueue) {
        self.queue = queue
    }

    /// 版の行を挿入します。
    ///
    /// 責務: 全項目を引数バインドで1行追加します。
    func insert(_ database: Database, _ row: Dataset) throws {
        let values: [(any DatabaseValueConvertible)?] = [
            row.id, row.prefecture, row.state, row.stamp, "https://example.invalid/a.zip", 1_000_000, row.activatedAt, row.dataYear, row.dataMonth,
            row.formatVersion, row.totalRows, row.importedCount, row.skippedOutOfScope, row.skippedAbolished,
            row.coverage[0], row.coverage[1], row.coverage[2], row.coverage[3]
        ]
        try database.execute(
            sql: """
                INSERT INTO road_regulation_datasets
                (id, prefectureCode, state, publicationStamp, sourceURL, downloadedAtMicroseconds, activatedAtMicroseconds, dataYear, dataMonth,
                 formatVersion, totalRowCount, importedCount, skippedOutOfScopeCount, skippedAbolishedCount,
                 coverageMinLatitude, coverageMaxLatitude, coverageMinLongitude, coverageMaxLongitude)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: StatementArguments(values)
        )
    }

    /// 規制の行を挿入します。
    ///
    /// 責務: 全項目を引数バインドで1行追加します。
    func insert(_ database: Database, _ row: Regulation) throws {
        let values: [(any DatabaseValueConvertible)?] = [
            row.id, row.dataset, row.uniqueKey, row.kind, row.speed, row.side, row.oneWay, row.perimeter, row.conditions, row.geometry
        ]
        try database.execute(
            sql: """
                INSERT INTO road_regulations
                (id, datasetID, uniqueKey, kind, speedLimitKph, sideCode, oneWayOrder, perimeterRoadIncluded, conditions, geometry)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: StatementArguments(values)
        )
    }

    /// 升目の行を挿入します。
    func insertCell(_ database: Database, dataset: String = "00000000-0000-0000-0000-0000000000a1", cell: Int64 = 1, regulation: Int64 = 1) throws {
        try database.execute(
            sql: "INSERT INTO road_regulation_cells (datasetID, cellKey, regulationID) VALUES (?, ?, ?)",
            arguments: [dataset, cell, regulation]
        )
    }

    /// 拒否件数の行を挿入します。
    func insertRejection(
        _ database: Database, dataset: String = "00000000-0000-0000-0000-0000000000a1", reason: String = "invalidSpeed", count: Int64 = 1
    ) throws {
        try database.execute(
            sql: "INSERT INTO road_regulation_dataset_rejections (datasetID, reason, count) VALUES (?, ?, ?)",
            arguments: [dataset, reason, count]
        )
    }

    /// 書込みが指定の拡張結果コードで拒否されることを検証します。
    ///
    /// 責務: 成功や別種のエラーでなく、期待した種類の制約違反で失敗したことを確認します。
    func assertRejected(
        _ label: String, code: ResultCode = .SQLITE_CONSTRAINT_CHECK, file: StaticString = #filePath, line: UInt = #line,
        _ write: (Database) throws -> Void
    ) {
        XCTAssertThrowsError(try queue.write(write), label, file: file, line: line) { error in
            XCTAssertEqual((error as? DatabaseError)?.extendedResultCode, code, "\(label): \(error)", file: file, line: line)
        }
    }

    /// 書込みが成功することを検証します(拒否テストの対照)。
    func assertAccepted(_ label: String, file: StaticString = #filePath, line: UInt = #line, _ write: (Database) throws -> Void) {
        XCTAssertNoThrow(try queue.write(write), label, file: file, line: line)
    }
}

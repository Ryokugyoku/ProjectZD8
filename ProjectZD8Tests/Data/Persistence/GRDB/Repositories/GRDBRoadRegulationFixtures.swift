import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 交通規制の保存・検索のテストが共有する、同一 Queue 上の Repository 群と、値を作る補助です。
struct GRDBRoadRegulationFixtures {
    /// テストが直接 SQL を流し込めるインメモリ DB Queue です。
    let queue: DatabaseQueue
    /// 検証対象の版の Repository です。
    let datasets: GRDBRoadRegulationDatasetRepository
    /// 検証対象の検索 Repository です。
    let query: GRDBRoadRegulationQueryRepository

    /// 空の DB へ2つの Repository を用意します。
    ///
    /// 責務: 同一 Queue 上に版の Repository(自分で Migration する)と検索 Repository を作ります。
    /// - Parameters:
    ///   - purgeBatchSize: 小分けの削除の件数。
    ///   - cellsPerQuery: 検索1回あたりの升目の数。
    /// - Throws: DB 作成または Migration の失敗。
    init(purgeBatchSize: Int = 2_000, cellsPerQuery: Int = 500) throws {
        queue = try DatabaseQueue()
        datasets = try GRDBRoadRegulationDatasetRepository(databaseQueue: queue, purgeBatchSize: purgeBatchSize)
        query = try GRDBRoadRegulationQueryRepository(databaseQueue: queue, cellsPerQuery: cellsPerQuery)
    }

    /// 都道府県コードを作ります。
    static func prefecture(_ number: Int) -> JapanesePrefectureCode {
        guard let code = JapanesePrefectureCode(number) else { preconditionFailure("テスト用の都道府県コードが範囲外です") }
        return code
    }

    /// 座標を作ります。
    static func point(_ latitude: Double, _ longitude: Double) -> GeoCoordinate {
        guard let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude) else {
            preconditionFailure("テスト用の座標が範囲外です")
        }
        return coordinate
    }

    /// 升目の key を作ります(行と列を 1 つの数から決める)。
    static func cell(_ number: Int) -> RoadRegulationCellKey {
        RoadRegulationCellKey(row: 20_000 + number / 1_000, column: 30_000 + number % 1_000)
    }

    /// 種類に合う形状を作ります(一時停止は点+進入方向、区域は三角形、他は線)。
    static func geometry(for kind: RoadRegulationKind, latitude: Double = 26.2) -> RoadRegulationGeometry {
        let base = point(latitude, 127.7)
        switch kind {
        case .stop:
            return RoadRegulationGeometry(parts: [
                RoadRegulationGeometryPart(role: .main, coordinates: [base]),
                RoadRegulationGeometryPart(role: .approach, coordinates: [point(latitude + 0.0001, 127.7)])
            ])
        case .speedLimitZone:
            let ring = [base, point(latitude + 0.001, 127.7), point(latitude, 127.701), base]
            return RoadRegulationGeometry(parts: [RoadRegulationGeometryPart(role: .main, coordinates: ring)])
        default:
            let line = [base, point(latitude + 0.0005, 127.7005)]
            return RoadRegulationGeometry(parts: [RoadRegulationGeometryPart(role: .main, coordinates: line)])
        }
    }

    /// 保存前の規制を作ります。種類ごとの制約(速度・一方通行の並び)を満たす値を自動で入れます。
    static func draft(
        key: String, kind: RoadRegulationKind = .speedLimitSection, speed: Int = 40,
        conditions: RoadRegulationConditions = .unconditional, latitude: Double = 26.2
    ) -> RoadRegulationDraft {
        let hasSpeed = kind == .speedLimitSection || kind == .speedLimitZone
        return RoadRegulationDraft(
            uniqueKey: key, kind: kind, speedLimitKph: hasSpeed ? speed : nil, side: kind == .speedLimitSection ? .bothSides : nil,
            oneWayOrder: kind == .oneWay ? .permittedDirection : nil, perimeterRoadIncluded: kind == .speedLimitZone ? true : nil,
            conditions: conditions, geometry: geometry(for: kind, latitude: latitude)
        )
    }

    /// 升目つきの規制を作ります。
    static func indexed(_ draft: RoadRegulationDraft, cells: [Int]) -> RoadRegulationIndexedDraft {
        RoadRegulationIndexedDraft(draft: draft, cells: cells.sorted().map(cell))
    }

    /// 版の取り込み開始の情報を作ります。
    static func datasetDraft(
        prefecture number: Int = 47, stamp: String = "202611010000", downloadedAt: Date = Date(timeIntervalSince1970: 1_700_000_000.5)
    ) -> RoadRegulationDatasetDraft {
        RoadRegulationDatasetDraft(
            prefecture: prefecture(number), publicationStamp: stamp,
            sourceURL: URL(string: "https://www.jartic.or.jp/d/opendata/\(stamp)/typeD_okinawa.zip")!, downloadedAt: downloadedAt
        )
    }

    /// 取り込みの結果を作ります(拒否は2種類・合計3件)。
    static func summary(imported: Int = 2) -> RoadRegulationImportSummary {
        guard let month = RoadRegulationDataMonth(year: 2026, month: 9),
              let coverage = GeoBoundingBox(minLatitude: 26.0, maxLatitude: 26.5, minLongitude: 127.5, maxLongitude: 128.0) else {
            preconditionFailure("テスト用の値が範囲外です")
        }
        let counts = RoadRegulationImportCounts(
            totalRows: 100, importedRegulations: imported, skippedOutOfScope: 80, skippedAbolished: 5,
            rejectedByReason: [.invalidSpeed: 2, .shapeMismatch: 1]
        )
        return RoadRegulationImportSummary(dataMonth: month, formatVersion: "2.1", counts: counts, coverage: coverage)
    }

    /// 取り込みを始めて規制を書き、有効にします。
    ///
    /// 責務: `beginImport` → `appendRegulations` → `activate` を順に呼びます。
    /// - Returns: 有効になった版。
    @discardableResult
    func importActive(
        prefecture number: Int = 47, stamp: String = "202611010000", regulations: [RoadRegulationIndexedDraft]
    ) throws -> RoadRegulationDataset {
        let id = try beginAndAppend(prefecture: number, stamp: stamp, regulations: regulations)
        return try datasets.activate(id, summary: Self.summary(imported: regulations.count), activatedAt: Date(timeIntervalSince1970: 1_700_000_100.25))
    }

    /// 取り込みを始めて規制を書きます(有効にはしない)。
    func beginAndAppend(
        prefecture number: Int = 47, stamp: String = "202611010000", regulations: [RoadRegulationIndexedDraft]
    ) throws -> RoadRegulationDatasetID {
        let id = try datasets.beginImport(Self.datasetDraft(prefecture: number, stamp: stamp))
        if !regulations.isEmpty { _ = try datasets.appendRegulations(regulations, to: id) }
        return id
    }

    /// 表の行数を返します(表名は固定の文字列だけを渡す)。
    func count(_ table: String) throws -> Int {
        try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") } ?? -1
    }

    /// 版の状態を返します。
    func state(of id: RoadRegulationDatasetID) throws -> String? {
        let sql = "SELECT state FROM road_regulation_datasets WHERE id = ?"
        return try queue.read { try String.fetchOne($0, sql: sql, arguments: [id.rawValue.uuidString.lowercased()]) }
    }
}

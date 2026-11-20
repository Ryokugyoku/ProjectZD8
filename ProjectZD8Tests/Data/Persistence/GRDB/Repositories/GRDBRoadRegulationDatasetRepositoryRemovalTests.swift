import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBRoadRegulationDatasetRepository` の退役・破棄・掃除(小分けの削除)を検証します。
@MainActor
final class GRDBRoadRegulationDatasetRepositoryRemovalTests: XCTestCase {
    private typealias Fixtures = GRDBRoadRegulationFixtures
    private static let tables = ["road_regulation_datasets", "road_regulation_dataset_rejections", "road_regulations", "road_regulation_cells"]

    /// 規制を `count` 件(各4升目)作ります。
    private func regulations(_ count: Int) -> [RoadRegulationIndexedDraft] {
        (0..<count).map { Fixtures.indexed(Fixtures.draft(key: "k\($0)"), cells: [$0 * 4, $0 * 4 + 1, $0 * 4 + 2, $0 * 4 + 3]) }
    }

    /// 4つの表の行数を、表名の順に返します。
    private func counts(_ fixtures: Fixtures) throws -> [Int] {
        try Self.tables.map { try fixtures.count($0) }
    }

    /// `retireActiveDataset` は、有効な版があれば true で retired にし、無ければ false です。
    ///
    /// 責務: 戻り値・状態・検索からの除外・他県の版が変わらないこと・2回目が false であることを確認します。
    func testRetireActiveDatasetReturnsTrueThenFalse() throws {
        let fixtures = try Fixtures()
        let target = try fixtures.importActive(prefecture: 47, regulations: [])
        let other = try fixtures.importActive(prefecture: 13, regulations: [])

        XCTAssertFalse(try fixtures.datasets.retireActiveDataset(for: Fixtures.prefecture(1)))
        XCTAssertTrue(try fixtures.datasets.retireActiveDataset(for: Fixtures.prefecture(47)))
        XCTAssertFalse(try fixtures.datasets.retireActiveDataset(for: Fixtures.prefecture(47)))

        XCTAssertEqual(try fixtures.state(of: target.id), "retired")
        XCTAssertEqual(try fixtures.state(of: other.id), "active")
        XCTAssertEqual(try fixtures.datasets.activeDatasets().map(\.id), [other.id])
    }

    /// `discard` は、小分け(3件ずつ)の削除でも、その版の行を4つの表から1行も残さず、他の版は変えません。
    ///
    /// 責務: 規制10件・升目40件・拒否件数を持つ版を削除し、別の県の版の行数が不変であることを確認します。
    func testDiscardRemovesEveryRowOfDatasetWithTinyBatches() throws {
        let fixtures = try Fixtures(purgeBatchSize: 3)
        let target = try fixtures.importActive(prefecture: 47, regulations: regulations(10))
        _ = try fixtures.datasets.retireActiveDataset(for: Fixtures.prefecture(47))
        let kept = try fixtures.importActive(prefecture: 13, regulations: regulations(5))
        XCTAssertEqual(try counts(fixtures), [2, 4, 15, 60])

        try fixtures.datasets.discard(target.id)

        XCTAssertEqual(try counts(fixtures), [1, 2, 5, 20])
        XCTAssertEqual(try fixtures.datasets.activeDatasets().map(\.id), [kept.id])
        let owners = try fixtures.queue.read { try String.fetchAll($0, sql: "SELECT DISTINCT datasetID FROM road_regulations") }
        XCTAssertEqual(owners, [kept.id.rawValue.uuidString.lowercased()])
    }

    /// 存在しない版の `discard` と、同じ版の2回目の `discard` は `notFound` です。
    ///
    /// 責務: id 不在の分類と、削除が1回目で完了していることを確認します。
    func testDiscardUnknownOrAlreadyDiscardedDatasetIsNotFound() throws {
        let fixtures = try Fixtures()
        let id = try fixtures.beginAndAppend(regulations: regulations(2))

        XCTAssertThrowsError(try fixtures.datasets.discard(RoadRegulationDatasetID(rawValue: UUID()))) {
            XCTAssertEqual($0 as? RoadRegulationRepositoryError, .notFound)
        }
        try fixtures.datasets.discard(id)
        XCTAssertThrowsError(try fixtures.datasets.discard(id)) {
            XCTAssertEqual($0 as? RoadRegulationRepositoryError, .notFound)
        }
    }

    /// active の版を `discard` すると、検索から外れて4つの表から消えます。
    ///
    /// 責務: active を直接渡しても、規制が検索結果から消え、行が残らないことを確認します。
    func testDiscardingActiveDatasetRemovesItFromSearchAndTables() throws {
        let fixtures = try Fixtures(purgeBatchSize: 3)
        let active = try fixtures.importActive(regulations: regulations(5))

        try fixtures.datasets.discard(active.id)

        XCTAssertEqual(try counts(fixtures), [0, 0, 0, 0])
        XCTAssertEqual(try fixtures.datasets.activeDatasets(), [])
        XCTAssertEqual(try fixtures.query.regulations(inCells: [Fixtures.cell(0)]), [])
    }

    /// 取り込み途中の版も `discard` で消え、前の有効な版は変わりません。
    ///
    /// 責務: 放棄された取り込みの後始末と、旧版の保持を確認します。
    func testDiscardingAbandonedImportKeepsPreviousActive() throws {
        let fixtures = try Fixtures(purgeBatchSize: 3)
        let old = try fixtures.importActive(regulations: regulations(4))
        let before = try counts(fixtures)
        let abandoned = try fixtures.beginAndAppend(stamp: "202612010000", regulations: regulations(7))

        try fixtures.datasets.discard(abandoned)

        XCTAssertEqual(try counts(fixtures), before)
        XCTAssertEqual(try fixtures.datasets.activeDatasets().map(\.id), [old.id])
    }

    /// `purgeInactiveDatasets` は retired と importing を消し、active を残します。
    ///
    /// 責務: 小分け(3件ずつ)の削除で、残骸のすべての行が4つの表から消え、active の行数が不変であることを確認します。
    func testPurgeInactiveRemovesRetiredAndImportingButKeepsActive() throws {
        let fixtures = try Fixtures(purgeBatchSize: 3)
        _ = try fixtures.importActive(prefecture: 47, stamp: "202610010000", regulations: regulations(8))
        let active47 = try fixtures.importActive(prefecture: 47, stamp: "202611010000", regulations: regulations(6))
        let active1 = try fixtures.importActive(prefecture: 1, regulations: regulations(2))
        _ = try fixtures.beginAndAppend(prefecture: 13, regulations: regulations(9))
        XCTAssertEqual(try counts(fixtures), [4, 6, 25, 100])

        try fixtures.datasets.purgeInactiveDatasets()

        XCTAssertEqual(try counts(fixtures), [2, 4, 8, 32])
        XCTAssertEqual(try fixtures.datasets.activeDatasets().map(\.id), [active1.id, active47.id])
        let states = try fixtures.queue.read { try String.fetchAll($0, sql: "SELECT state FROM road_regulation_datasets") }
        XCTAssertEqual(Set(states), ["active"])
    }

    /// 掃除する物が無くても成功し、有効な版を変えません。
    ///
    /// 責務: 空の DB と、active だけの DB で `purgeInactiveDatasets` が何も消さないことを確認します。
    func testPurgeWithNothingToRemoveSucceeds() throws {
        let fixtures = try Fixtures()
        XCTAssertNoThrow(try fixtures.datasets.purgeInactiveDatasets())
        _ = try fixtures.importActive(regulations: regulations(2))
        let before = try counts(fixtures)

        try fixtures.datasets.purgeInactiveDatasets()

        XCTAssertEqual(try counts(fixtures), before)
    }
}

import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 製品 DB を開けない時に交通規制の Repository が利用不能な実装になり、開ける時は GRDB 実装で動くことを検証します。
@MainActor
final class ProductDatabaseRepositoryFactoryRoadRegulationTests: XCTestCase {
    /// DB を開けなかった失敗を表すテスト用エラーです。
    private struct OpenFailure: Error, Equatable {}

    /// 製品 DB を開けなければ、版・検索とも利用不能な実装が返り、診断が `roadRegulations` で1件ずつ残ります。
    ///
    /// 責務: 返った Repository の型・操作の失敗・診断の保存先と元のエラーを確認します。
    func testUnopenableDatabaseReturnsUnavailableRepositoriesWithDiagnostics() {
        let spy = ProductDatabasePreparationDiagnosticsSpy()
        let database = ApplicationDatabaseConnection(openDatabaseQueue: { throw OpenFailure() })
        let factory = ProductDatabaseRepositoryFactory(diagnostics: spy)

        let datasets = factory.makeRoadRegulationDatasetRepository(database: database)
        let query = factory.makeRoadRegulationQueryRepository(database: database)

        XCTAssertTrue(datasets is UnavailableRoadRegulationDatasetRepository)
        XCTAssertTrue(query is UnavailableRoadRegulationQueryRepository)
        XCTAssertEqual(spy.entries.map(\.storage), [.roadRegulations, .roadRegulations])
        XCTAssertTrue(spy.entries.allSatisfy { $0.error as? OpenFailure == OpenFailure() })
        XCTAssertThrowsError(try datasets.activeDatasets()) { XCTAssertEqual($0 as? RoadRegulationRepositoryError, .unavailable) }
        XCTAssertThrowsError(try query.regulations(inCells: [])) { XCTAssertEqual($0 as? RoadRegulationRepositoryError, .unavailable) }
    }

    /// 製品 DB を開ければ、GRDB 実装が返り、診断は残らず、取り込みから検索までの流れが動きます。
    ///
    /// 責務: 成功時に利用不能へ差し替えないことと、返った2つの Repository が同じ DB を共有して往復できることを確認します。
    func testOpenableDatabaseReturnsWorkingGRDBRepositoriesWithoutDiagnostics() throws {
        let queue = try DatabaseQueue()
        let database = ApplicationDatabaseConnection(openDatabaseQueue: { queue })
        let spy = ProductDatabasePreparationDiagnosticsSpy()
        let factory = ProductDatabaseRepositoryFactory(diagnostics: spy)

        let datasets = factory.makeRoadRegulationDatasetRepository(database: database)
        let query = factory.makeRoadRegulationQueryRepository(database: database)

        XCTAssertTrue(datasets is GRDBRoadRegulationDatasetRepository)
        XCTAssertTrue(query is GRDBRoadRegulationQueryRepository)
        XCTAssertTrue(spy.entries.isEmpty)
        let id = try datasets.beginImport(GRDBRoadRegulationFixtures.datasetDraft())
        let draft = GRDBRoadRegulationFixtures.draft(key: "a")
        XCTAssertEqual(try datasets.appendRegulations([GRDBRoadRegulationFixtures.indexed(draft, cells: [1])], to: id), 1)
        _ = try datasets.activate(id, summary: GRDBRoadRegulationFixtures.summary(), activatedAt: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(try query.regulations(inCells: [GRDBRoadRegulationFixtures.cell(1)]).map(\.uniqueKey), ["a"])
    }
}

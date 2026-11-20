import Foundation
import XCTest
@testable import ProjectZD8

/// `PurgeRoadRegulationLeftoversUseCase` が、取り込み途中(importing)と退役(retired)の版と、残ったダウンロードを消し、有効な版を残すことを検証します。
@MainActor
final class PurgeRoadRegulationLeftoversUseCaseTests: XCTestCase {
    private typealias Values = RoadRegulationTestValues

    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RoadRegulationPurge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try await super.tearDown()
    }

    /// 責務: 掃除を期限つきで実行し、結果を返します。
    private func purge(
        _ repository: RoadRegulationDatasetRepositorySpy,
        _ source: RoadRegulationSourceFake
    ) async -> Result<Void, any Error>? {
        let useCase = PurgeRoadRegulationLeftoversUseCase(datasets: repository, source: source)
        return await TestBoundedAsyncRun { try await useCase.execute() }.result(on: self)
    }

    /// 責務: 帳面を共有する Repository と配布元の偽物を作ります。
    private func makeFakes() -> (RoadRegulationDatasetRepositorySpy, RoadRegulationSourceFake) {
        let log = RoadRegulationImportCallLog()
        let source = RoadRegulationSourceFake(catalog: Values.catalog([]), downloadDirectory: directory, log: log)
        return (RoadRegulationDatasetRepositorySpy(log: log), source)
    }

    /// 未完了の版と退役した版を消し、残ったダウンロードも掃除し、有効な版は残します。
    ///
    /// 責務: 掃除の対象と、ダウンロードの残骸の掃除を確認します。
    func testPurgesInactiveDatasetsAndLeftoverDownloads() async throws {
        let (repository, source) = makeFakes()
        let active = Values.dataset(Values.prefecture(47))
        repository.seedActive(active)
        repository.seedInactive(RoadRegulationDatasetID(rawValue: UUID()), prefecture: Values.prefecture(47), state: .importing)
        repository.seedInactive(RoadRegulationDatasetID(rawValue: UUID()), prefecture: Values.prefecture(13), state: .retired)

        let finished = await purge(repository, source)
        let result = try XCTUnwrap(finished)

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(repository.purgeCount, 1)
        XCTAssertEqual(source.leftoverRemovalCount, 1)
        XCTAssertTrue(repository.importingDatasetIDs.isEmpty)
        XCTAssertTrue(repository.retiredDatasetIDs.isEmpty)
        XCTAssertEqual(repository.currentActiveDatasets, [active])
    }

    /// 掃除は通信しません(一覧もダウンロードも取りに行きません)。
    ///
    /// 責務: 画面を開いた時の掃除が通信を起こさないことを確認します。
    func testPurgeDoesNotTouchNetwork() async throws {
        let (repository, source) = makeFakes()

        let finished = await purge(repository, source)
        let result = try XCTUnwrap(finished)

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(source.catalogCallCount, 0)
        XCTAssertTrue(source.downloadedEntries.isEmpty)
    }

    /// 版の掃除が保存の失敗なら、失敗を握りつぶさずに伝えます。
    ///
    /// 責務: 掃除の失敗が伝わることを確認します。
    func testPurgeFailureIsReported() async throws {
        let (repository, source) = makeFakes()
        repository.fail(.purgeInactiveDatasets, with: .unavailable)

        let finished = await purge(repository, source)
        let result = try XCTUnwrap(finished)

        XCTAssertThrowsError(try result.get())
    }
}

import XCTest
@testable import ProjectZD8

/// `EvaluateSessionRoadRegulationsUseCase` が、位置・版・Raw ログ・規制の各 Repository の失敗を、
/// 空の結果に潰さずそのまま投げることを検証します(設計書 §3.7「判定」の 7、TB9)。結果は期限(2秒)つきで待ちます。
@MainActor
final class EvaluateSessionRoadRegulationsUseCaseFailureTests: XCTestCase {
    private typealias Harness = RoadRegulationEvaluationUseCaseHarness
    private var harness: Harness!

    override func setUp() async throws {
        try await super.setUp()
        harness = Harness()
        harness.regulations.replaceRegulations([Harness.eastRoad()])
        try harness.seedTrack(count: 41)
        harness.seedRaw(count: 41)
        harness.seedOkinawaDataset()
    }

    override func tearDown() async throws {
        harness = nil
        try await super.tearDown()
    }

    /// 責務: ユースケースを動かし、期限内に投げたエラーを返します(成功したら失敗にします)。
    private func failure(_ useCase: EvaluateSessionRoadRegulationsUseCase) async -> (any Error)? {
        await harness.start(useCase).failure(on: self)
    }

    /// 責務: 位置の Repository の失敗を、そのまま投げることを確かめます(`.noTrack` にしない)。
    func testLocationRepositoryFailureIsThrown() async {
        let error = await failure(harness.makeUseCase(locationRepository: RoadRegulationFailingLocationRepository()))
        XCTAssertEqual(error as? ConnectionSessionRepositoryError, .unavailable)
    }

    /// 責務: 版の Repository の失敗を、そのまま投げることを確かめます(`.noRegulationData` にしない)。
    func testDatasetRepositoryFailureIsThrown() async {
        harness.datasets.fail(.activeDatasets, with: .unavailable)
        let error = await failure(harness.makeUseCase())
        XCTAssertEqual(error as? RoadRegulationRepositoryError, .unavailable)
    }

    /// 責務: Raw ログの Repository の失敗を、そのまま投げることを確かめます(車速なしにしない)。
    func testRawLogRepositoryFailureIsThrown() async {
        harness.rawLogs.error = .unavailable
        let error = await failure(harness.makeUseCase())
        XCTAssertEqual(error as? ConnectionSessionRepositoryError, .unavailable)
    }

    /// 責務: 規制の検索の失敗を、そのまま投げることを確かめます(`.noRegulationData` にしない)。
    func testRegulationQueryFailureIsThrown() async {
        harness.regulations.fail(with: .integrityConflict)
        let error = await failure(harness.makeUseCase())
        XCTAssertEqual(error as? RoadRegulationRepositoryError, .integrityConflict)
    }
}

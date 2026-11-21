import Foundation
import XCTest
@testable import ProjectZD8

/// 判定のユースケースの結果を解析のポートの結果へ写すアダプターを検証します(設計書 §3.6「Adapter の流れ」・§7 TC2)。
///
/// 判定と版の一覧は closure の Fake で差し替え、呼び出しの引数と回数を記録します。
@MainActor
final class RoadRegulationSessionReviewAdapterTests: XCTestCase {
    private typealias Fixtures = RoadRegulationSessionReviewMapperFixtures

    /// Fake が投げるテスト用のエラーです(型と値で見分けます)。
    private struct AdapterTestError: Error, Equatable {
        /// エラーを見分ける番号です。
        let code: Int
    }

    /// 判定の closure が返す結果です。
    private var evaluateResult: Result<SessionRoadRegulationEvaluationOutcome, any Error> = .success(.noTrack)
    /// 版の一覧の closure が返す結果です。
    private var listResult: Result<[RoadRegulationDataset], any Error> = .success([])
    /// 判定の closure が受け取ったセッション ID の記録です。
    private var evaluatedSessionIDs: [ConnectionSessionID] = []
    /// 版の一覧の closure が呼ばれた回数です。
    private var listCallCount = 0

    /// 責務: 記録つきの closure を渡したアダプターを作ります。
    /// - Returns: アダプター。
    private func makeAdapter() -> RoadRegulationSessionReviewAdapter {
        RoadRegulationSessionReviewAdapter(
            evaluate: { [unowned self] sessionID in
                evaluatedSessionIDs.append(sessionID)
                return try evaluateResult.get()
            },
            listDatasets: { [unowned self] in
                listCallCount += 1
                return try listResult.get()
            },
            sourceURL: Fixtures.sourceURL
        )
    }

    /// 責務: 県・基準月・取得日時を指定して版を作ります。
    private func dataset(_ prefecture: Int, _ year: Int, _ month: Int, downloadedAt: TimeInterval) -> RoadRegulationDataset {
        RoadRegulationTestValues.dataset(
            RoadRegulationTestValues.prefecture(prefecture), month: RoadRegulationTestValues.month(year, month),
            downloadedAt: Date(timeIntervalSince1970: downloadedAt)
        )
    }

    /// 責務: 県 47・2026年9月と県 13・2026年8月を使った報告で `.evaluated` を返すよう設定します。
    /// - Returns: 設定した報告。
    @discardableResult
    private func setEvaluatedReport() -> SessionRoadRegulationReport {
        let traversal = Fixtures.speedLimitTraversal(from: 0, to: 10, sequences: 0...10)
        let report = Fixtures.report(
            speedLimit: [SpeedLimitJudgement(traversal: traversal, limitKph: 40, verdict: .exceeded(maxKph: 50, exceededSeconds: 3))],
            hasVehicleSpeed: false,
            datasets: [Fixtures.reference(47, 2026, 9), Fixtures.reference(13, 2026, 8)]
        )
        evaluateResult = .success(.evaluated(report))
        return report
    }

    /// 責務: アダプターを呼び、照合結果を返します(投げたら失敗)。
    private func reviewed(_ sessionID: ConnectionSessionID = ConnectionSessionID()) async throws -> SessionRoadRegulationReview {
        let result = try await makeAdapter().review(sessionID: sessionID)
        guard case .reviewed(let review) = result else {
            XCTFail("reviewed ではありません: \(result)")
            throw AdapterTestError(code: -1)
        }
        return review
    }

    /// 責務: アダプターが投げたエラーを返します(投げなければ失敗)。
    private func thrownError() async -> (any Error)? {
        do {
            let result = try await makeAdapter().review(sessionID: ConnectionSessionID())
            XCTFail("エラーが投げられませんでした: \(result)")
            return nil
        } catch {
            return error
        }
    }

    /// 責務: 位置が無い結果はそのまま写り、版の一覧を読まないことを確かめます。
    func testNoTrackPassesThroughWithoutListingDatasets() async throws {
        evaluateResult = .success(.noTrack)

        let result = try await makeAdapter().review(sessionID: ConnectionSessionID())

        XCTAssertEqual(result, .noTrack)
        XCTAssertEqual(listCallCount, 0)
    }

    /// 責務: 規制データが無い結果はそのまま写り、版の一覧を読まないことを確かめます。
    func testNoRegulationDataPassesThroughWithoutListingDatasets() async throws {
        evaluateResult = .success(.noRegulationData)

        let result = try await makeAdapter().review(sessionID: ConnectionSessionID())

        XCTAssertEqual(result, .noRegulationData)
        XCTAssertEqual(listCallCount, 0)
    }

    /// 責務: 受け取ったセッション ID がそのまま判定へ渡ることを確かめます。
    func testSessionIDIsPassedToEvaluate() async throws {
        let sessionID = ConnectionSessionID()
        evaluateResult = .success(.noTrack)

        _ = try await makeAdapter().review(sessionID: sessionID)

        XCTAssertEqual(evaluatedSessionIDs, [sessionID])
    }

    /// 責務: 利用日は、県と基準月の両方が一致する版の取得日時の最大で、一致しない版はより新しくても採らないことを確かめます。
    func testUsedOnIsLatestDownloadOfMatchingDatasets() async throws {
        setEvaluatedReport()
        listResult = .success([
            dataset(47, 2026, 9, downloadedAt: 1_790_000_000),
            dataset(13, 2026, 8, downloadedAt: 1_790_500_000),
            dataset(47, 2026, 8, downloadedAt: 1_799_000_000),
            dataset(14, 2026, 9, downloadedAt: 1_799_500_000),
        ])

        let review = try await reviewed()

        XCTAssertEqual(review.usedOn, Date(timeIntervalSince1970: 1_790_500_000))
        XCTAssertEqual(listCallCount, 1)
    }

    /// 責務: 一致する版が無ければ利用日は nil であることを確かめます。
    func testUsedOnIsNilWithoutMatchingDataset() async throws {
        setEvaluatedReport()
        listResult = .success([dataset(47, 2026, 8, downloadedAt: 1_790_000_000), dataset(1, 2026, 9, downloadedAt: 1_790_000_000)])

        let review = try await reviewed()

        XCTAssertNil(review.usedOn)
    }

    /// 責務: 版の一覧が空でも利用日は nil で、照合結果を返すことを確かめます。
    func testUsedOnIsNilWithEmptyDatasetList() async throws {
        setEvaluatedReport()
        listResult = .success([])

        let review = try await reviewed()

        XCTAssertNil(review.usedOn)
    }

    /// 責務: 使える点が0点の空の報告(使った版も無い)は、entries が空の照合結果になり、利用日は nil であることを確かめます。
    func testEmptyEvaluatedReportBecomesEmptyReview() async throws {
        evaluateResult = .success(.evaluated(Fixtures.report(hasVehicleSpeed: false, datasets: [])))
        listResult = .success([dataset(47, 2026, 9, downloadedAt: 1_790_000_000)])

        let review = try await reviewed()

        XCTAssertEqual(review.entries, [])
        XCTAssertEqual(review.datasets, [])
        XCTAssertNil(review.usedOn)
    }

    /// 責務: 照合結果は Mapper の写しで、範囲の値と配布ページの URL を持つことを確かめます。
    func testEvaluatedReportIsMappedWithSourceURL() async throws {
        let report = setEvaluatedReport()
        listResult = .success([dataset(47, 2026, 9, downloadedAt: 1_790_000_000)])

        let review = try await reviewed()

        let expectedEntries = RoadRegulationSessionReviewMapper()
            .review(from: report, usedOn: nil, sourceURL: Fixtures.sourceURL).entries
        XCTAssertEqual(review.entries, expectedEntries)
        XCTAssertEqual(review.entries.map(\.outcome), [.possibleIssue])
        XCTAssertFalse(review.hasVehicleSpeed)
        XCTAssertEqual(review.datasets, [Fixtures.reference(47, 2026, 9), Fixtures.reference(13, 2026, 8)])
        XCTAssertEqual(review.sourceURL, Fixtures.sourceURL)
        XCTAssertEqual(review.usedOn, Date(timeIntervalSince1970: 1_790_000_000))
    }

    /// 責務: 判定が投げたエラーが、そのまま(型と値)投げられ、版の一覧を読まないことを確かめます。
    func testEvaluateErrorIsRethrown() async {
        evaluateResult = .failure(AdapterTestError(code: 7))

        let error = await thrownError()

        XCTAssertEqual(error as? AdapterTestError, AdapterTestError(code: 7))
        XCTAssertEqual(listCallCount, 0)
    }

    /// 責務: 判定の取消(`CancellationError`)が、そのまま投げられることを確かめます。
    func testEvaluateCancellationIsRethrown() async {
        evaluateResult = .failure(CancellationError())

        let error = await thrownError()

        XCTAssertTrue(error is CancellationError, "CancellationError ではありません: \(String(describing: error))")
        XCTAssertEqual(listCallCount, 0)
    }

    /// 責務: 版の一覧のエラーが、そのまま(型と値)投げられることを確かめます(成功や空に潰さない)。
    func testListDatasetsErrorIsRethrown() async {
        setEvaluatedReport()
        listResult = .failure(AdapterTestError(code: 9))

        let error = await thrownError()

        XCTAssertEqual(error as? AdapterTestError, AdapterTestError(code: 9))
        XCTAssertEqual(listCallCount, 1)
    }
}

import Foundation
import XCTest
@testable import ProjectZD8

/// 交通規制の照合のモデルが、ポートの結果から状態を作ること(内容・status・再試行)を検証します(設計書 §3.4・§6.2・§6.3・§7 TC3)。
///
/// 期待値は部品を呼ばず、入力の entries から仕様の規則で手で書きます(`SessionRoadRegulationReviewModelTestValues`)。
@MainActor
final class SessionRoadRegulationReviewModelLoadTests: XCTestCase {
    private typealias Values = SessionRoadRegulationReviewModelTestValues

    /// モデルと部品の組です。
    private var harness = SessionRoadRegulationReviewModelHarness()

    /// 責務: 止めた呼び出しを必ず再開し、終わらないテストを残しません。
    override func tearDown() async throws {
        harness.openAllGates()
        try await super.tearDown()
    }

    /// 責務: 件数の値を作ります。
    private func count(_ outcome: SessionRoadRegulationReviewOutcome, _ key: String, _ count: Int) -> SessionRoadRegulationReviewCount {
        SessionRoadRegulationReviewCount(outcome: outcome, labelKey: key, category: Values.category(outcome), count: count)
    }

    /// 責務: 種類ごとのまとめが4件・種類の順で、件数0の結果を含まないことを確かめます。
    func testReviewedBuildsSummaries() async {
        await harness.load()

        let expected: [SessionRoadRegulationReviewKindSummary] = [
            .init(kind: .speedLimit, titleKey: "road_regulation.kind.speed_limit", total: 2, counts: [
                count(.possibleIssue, "road_regulation.verdict.speed_limit.exceeded", 1),
                count(.unregulated, "road_regulation.verdict.speed_limit.unregulated", 1),
            ]),
            .init(kind: .stop, titleKey: "road_regulation.kind.stop", total: 1, counts: [
                count(.compliant, "road_regulation.verdict.stop.stopped", 1),
            ]),
            .init(kind: .oneWay, titleKey: "road_regulation.kind.one_way", total: 1, counts: [
                count(.undeterminable, "analysis.road_regulation.outcome.undetermined", 1),
            ]),
            .init(kind: .slowDown, titleKey: "road_regulation.kind.slow_down", total: 0, counts: []),
        ]
        XCTAssertEqual(harness.state.summaries, expected)
    }

    /// 責務: 一覧は既定の絞り込み(attention)で、確認が必要な行だけと、空の時の文言キーを持つことを確かめます。
    func testReviewedBuildsAttentionSections() async {
        await harness.load()

        let rows = Values.standardRows
        let expected: [SessionRoadRegulationReviewSection] = [
            .init(kind: .speedLimit, titleKey: "road_regulation.kind.speed_limit", totalCount: 2, rows: [rows[1]], emptyMessageKey: nil),
            .init(kind: .stop, titleKey: "road_regulation.kind.stop", totalCount: 1, rows: [],
                  emptyMessageKey: "analysis.road_regulation.list.empty_attention"),
            .init(kind: .oneWay, titleKey: "road_regulation.kind.one_way", totalCount: 1, rows: [rows[3]], emptyMessageKey: nil),
            .init(kind: .slowDown, titleKey: "road_regulation.kind.slow_down", totalCount: 0, rows: [],
                  emptyMessageKey: "analysis.road_regulation.list.empty_kind"),
        ]
        XCTAssertEqual(harness.state.filter, .attention)
        XCTAssertEqual(harness.state.sections, expected)
    }

    /// 責務: 重ね合わせは行のある種類だけ・種類の順で、run・凡例・強調が §3.4 の規則どおりであり、選択は nil であることを確かめます。
    func testReviewedBuildsOverlaysWithoutSelection() async {
        await harness.load()

        XCTAssertNil(harness.state.selectedRowID)
        XCTAssertEqual(harness.state.overlays, Values.standardOverlays())
    }

    /// 責務: 注記(指定なしの説明だけ)と出典(版の文字・利用日・配布ページ)が入ることを確かめます。
    func testReviewedBuildsNoticesAndAttribution() async {
        await harness.load()

        let style = Date.FormatStyle(
            date: .numeric, time: .omitted, locale: SessionRoadRegulationReviewModelHarness.locale,
            calendar: Calendar(identifier: .gregorian), timeZone: SessionRoadRegulationReviewModelHarness.timeZone
        )
        let expected = SessionRoadRegulationReviewAttribution(
            datasetTexts: ["<road_regulation.prefecture.47> (2026-9)"],
            usedOnText: "U=" + Values.usedOn.formatted(style),
            sourceURL: Values.sourceURL
        )
        XCTAssertEqual(harness.state.notices, [.unregulatedExplained])
        XCTAssertEqual(harness.state.attribution, expected)
    }

    /// 責務: 車速が無く Raw が iCloud にある時は、iCloud の注記が先頭に入ることを確かめます(評価した raw を使う)。
    func testNoticesUseEvaluatedRawLogInCloud() async {
        await harness.load(Values.standardReview(hasVehicleSpeed: false), raw: .inCloud)

        XCTAssertEqual(harness.state.notices, [.speedInCloud, .unregulatedExplained])
    }

    /// 責務: 車速が無く Raw が読めなかった時は「車速の記録がない」注記、使った版が無い時は範囲外の注記が入ることを確かめます。
    func testNoticesForUnreadableRawLogAndMissingDatasets() async {
        await harness.load(Values.standardReview(hasVehicleSpeed: false, datasets: []), raw: .unreadable)

        XCTAssertEqual(harness.state.notices, [.speedNotRecorded, .outsideData, .unregulatedExplained])
    }

    /// 責務: 位置が無い・規制データが無い結果では、その status になり、内容・重ね合わせが空、出典が `.empty` であることを確かめます。
    func testNoTrackAndNoRegulationDataLeaveContentEmpty() async {
        let cases: [(SessionRoadRegulationReviewResult, SessionRoadRegulationReviewStatus)] = [
            (.noTrack, .noTrack), (.noRegulationData, .noRegulationData),
        ]
        for (result, status) in cases {
            let harness = SessionRoadRegulationReviewModelHarness()
            harness.enqueue(.success(result))
            harness.sendReadiness(.ready(.onDevice))
            await harness.waitForStatus(status)

            let expected = SessionRoadRegulationReviewState(sessionID: harness.sessionID, status: status)
            XCTAssertEqual(harness.state, expected, "\(status)")
        }
    }

    /// 責務: 取消以外のエラーは failed になり、内容が空であることを確かめます(成功や空データに潰さない)。
    func testErrorBecomesFailed() async {
        harness.enqueue(.failure(URLError(.cannotOpenFile)))

        harness.sendReadiness(.ready(.onDevice))
        await harness.waitForStatus(.failed)

        XCTAssertEqual(harness.state, SessionRoadRegulationReviewState(sessionID: harness.sessionID, status: .failed))
    }

    /// 責務: failed の時の再試行は、同じ raw で呼び直して loaded になることを確かめます。
    func testRetryAfterFailureCallsAgainWithSameRawLog() async {
        harness.enqueue(.failure(URLError(.cannotOpenFile)))
        harness.sendReadiness(.ready(.inCloud))
        await harness.waitForStatus(.failed)
        harness.enqueue(.success(.reviewed(Values.standardReview(hasVehicleSpeed: false))))

        harness.send(.retryRequested)
        await harness.waitForCompletion(ofCall: 1)
        await harness.waitForStatus(.loaded)

        XCTAssertEqual(harness.port.calls, [harness.sessionID, harness.sessionID])
        XCTAssertEqual(harness.state.notices.first, .speedInCloud)
    }

    /// 責務: loaded の時の再試行は何もしないことを確かめます。
    func testRetryWhileLoadedDoesNothing() async {
        await harness.load()
        let before = harness.state

        harness.send(.retryRequested)
        await harness.settle()

        XCTAssertEqual(harness.port.calls.count, 1)
        XCTAssertEqual(harness.state, before)
    }

    /// 責務: 評価中の再試行は呼び直さないことを確かめます。
    func testRetryWhileEvaluatingDoesNothing() async {
        let gate = harness.enqueue(.success(.reviewed(Values.standardReview())), held: true)
        harness.sendReadiness(.ready(.onDevice))
        await harness.waitForWaiting(on: gate)

        harness.send(.retryRequested)
        await harness.settle()

        XCTAssertEqual(harness.port.calls.count, 1)
        XCTAssertEqual(harness.port.cancelledCalls, [])
        XCTAssertEqual(harness.state.status, .evaluating)
    }

    /// 責務: 結果が出る前(idle)や待ちの段階の再試行は呼ばないことを確かめます。
    func testRetryWithoutFailureOrReadyDoesNothing() async {
        harness.send(.retryRequested)
        harness.sendReadiness(.waitingForRawLog)
        harness.send(.retryRequested)
        await harness.settle()

        XCTAssertEqual(harness.port.calls, [])
        XCTAssertEqual(harness.state.status, .waitingForRawLog)
    }

    /// 責務: failed の後に待ちの段階へ戻ってからの再試行は、最後の readiness が ready でないので呼ばないことを確かめます。
    func testRetryAfterFallingBackFromFailureDoesNothing() async {
        harness.enqueue(.failure(URLError(.cannotOpenFile)))
        harness.sendReadiness(.ready(.onDevice))
        await harness.waitForStatus(.failed)
        harness.sendReadiness(.waitingForRawLog)

        harness.send(.retryRequested)
        await harness.settle()

        XCTAssertEqual(harness.port.calls.count, 1)
        XCTAssertEqual(harness.state.status, .waitingForRawLog)
    }
}

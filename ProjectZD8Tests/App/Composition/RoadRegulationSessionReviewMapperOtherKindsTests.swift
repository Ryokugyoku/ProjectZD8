import Foundation
import XCTest
@testable import ProjectZD8

/// 判定の報告を解析の照合結果へ写す Mapper の、一時停止・一方通行・徐行の写しを検証します(設計書 §3.6 の表・§7 TC2)。
///
/// 一時停止の両端は通過の「接近の開始」と「到達」、一方通行と徐行の両端は区間の両端です。
@MainActor
final class RoadRegulationSessionReviewMapperOtherKindsTests: XCTestCase {
    private typealias Fixtures = RoadRegulationSessionReviewMapperFixtures
    private typealias Judgement = RoadRegulationJudgementFixtures

    /// 一時停止の接近の開始の印(時刻 6 秒・連番 10。`stopPassage` の連番の決まり)です。
    private let stopStart = RoadRegulationJudgementFixtures.mark(at: 6, sequence: 10)
    /// 一時停止の到達の印(時刻 9 秒・連番 14)です。
    private let stopReached = RoadRegulationJudgementFixtures.mark(at: 9, sequence: 14)
    /// 一方通行・徐行の区間の開始の印です。
    private let sectionStart = RoadRegulationJudgementFixtures.mark(at: 20, sequence: 21)
    /// 一方通行・徐行の区間の終了の印です。
    private let sectionEnd = RoadRegulationJudgementFixtures.mark(at: 35, sequence: 30)

    /// 責務: 報告を既定の Mapper で写し、entry を返します。
    /// - Parameter report: 判定の報告。
    /// - Returns: 写した entry の一覧。
    private func entries(of report: SessionRoadRegulationReport) -> [SessionRoadRegulationReviewEntry] {
        RoadRegulationSessionReviewMapper().review(from: report, usedOn: nil, sourceURL: Fixtures.sourceURL).entries
    }

    /// 責務: 一時停止の判定1件を写します。
    private func mapStop(_ verdict: StopVerdict) -> [SessionRoadRegulationReviewEntry] {
        let judgement = StopJudgement(passage: Judgement.stopPassage(startedAt: 6, reachedAt: 9), verdict: verdict)
        return entries(of: Fixtures.report(stops: [judgement]))
    }

    /// 責務: 一方通行の判定1件を写します。
    private func mapOneWay(_ verdict: OneWayVerdict) -> [SessionRoadRegulationReviewEntry] {
        let traversal = Fixtures.oneWayTraversal(from: 20, to: 35, sequences: 21...30)
        return entries(of: Fixtures.report(oneWay: [OneWayJudgement(traversal: traversal, verdict: verdict)]))
    }

    /// 責務: 徐行の判定1件を写します。
    private func mapSlowDown(_ verdict: SlowDownVerdict) -> [SessionRoadRegulationReviewEntry] {
        let traversal = Fixtures.slowDownTraversal(from: 20, to: 35, sequences: 21...30)
        return entries(of: Fixtures.report(slowDown: [SlowDownJudgement(traversal: traversal, verdict: verdict)]))
    }

    /// 責務: 停止した一時停止は compliant で、両端が接近の開始と到達、数値なしであることを確かめます。
    func testStoppedIsCompliantFromApproachToReached() {
        let expected = Fixtures.entry(.stop, .compliant, key: "road_regulation.verdict.stop.stopped", start: stopStart, end: stopReached)

        XCTAssertEqual(mapStop(.stopped), [expected])
    }

    /// 責務: 停止していない一時停止は possibleIssue で、最低速度を数値に持つことを確かめます。
    func testNotStoppedIsPossibleIssueWithMinimum() {
        let expected = Fixtures.entry(
            .stop, .possibleIssue, key: "road_regulation.verdict.stop.not_stopped", start: stopStart, end: stopReached,
            figures: SessionRoadRegulationReviewFigures(minimumKph: 7.5)
        )

        XCTAssertEqual(mapStop(.notStopped(minimumKph: 7.5)), [expected])
    }

    /// 責務: 判定できない一時停止は undeterminable で、理由と理由のキーを持ち、数値なしであることを確かめます。
    func testStopUndeterminableCarriesReason() {
        let expected = Fixtures.entry(
            .stop, .undeterminable, key: "road_regulation.undetermined.track_gap", reason: .trackGap, start: stopStart, end: stopReached
        )

        XCTAssertEqual(mapStop(.undeterminable(.trackGap)), [expected])
    }

    /// 責務: 指定の向きの一方通行は compliant で、両端が区間の両端、数値なしであることを確かめます。
    func testFollowedDirectionIsCompliant() {
        let expected = Fixtures.entry(
            .oneWay, .compliant, key: "road_regulation.verdict.one_way.followed_direction", start: sectionStart, end: sectionEnd
        )

        XCTAssertEqual(mapOneWay(.followedDirection), [expected])
    }

    /// 責務: 逆走の可能性は possibleIssue で、逆方向の距離を数値に持つことを確かめます。
    func testPossibleWrongWayIsPossibleIssueWithDistance() {
        let expected = Fixtures.entry(
            .oneWay, .possibleIssue, key: "road_regulation.verdict.one_way.possible_wrong_way", start: sectionStart, end: sectionEnd,
            figures: SessionRoadRegulationReviewFigures(wrongWayDistanceMeters: 120.6)
        )

        XCTAssertEqual(mapOneWay(.possibleWrongWay(distanceMeters: 120.6)), [expected])
    }

    /// 責務: 判定できない一方通行は undeterminable で、理由と理由のキーを持つことを確かめます。
    func testOneWayUndeterminableCarriesReason() {
        let expected = Fixtures.entry(
            .oneWay, .undeterminable, key: "road_regulation.undetermined.heading_unknown", reason: .headingUnknown,
            start: sectionStart, end: sectionEnd
        )

        XCTAssertEqual(mapOneWay(.undeterminable(.headingUnknown)), [expected])
    }

    /// 責務: 徐行の通過は observedOnly で、最高速度と目安の速度を数値に持つことを確かめます。
    func testObservedSlowDownIsObservedOnlyWithFigures() {
        let expected = Fixtures.entry(
            .slowDown, .observedOnly, key: "road_regulation.verdict.slow_down.observed", start: sectionStart, end: sectionEnd,
            figures: SessionRoadRegulationReviewFigures(maximumKph: 12.4, referenceKph: 10)
        )

        XCTAssertEqual(mapSlowDown(.observed(maxKph: 12.4, referenceKph: 10)), [expected])
    }

    /// 責務: 判定できない徐行は undeterminable で、理由と理由のキーを持ち、数値なしであることを確かめます。
    func testSlowDownUndeterminableCarriesReason() {
        let expected = Fixtures.entry(
            .slowDown, .undeterminable, key: "road_regulation.undetermined.low_accuracy", reason: .lowAccuracy,
            start: sectionStart, end: sectionEnd
        )

        XCTAssertEqual(mapSlowDown(.undeterminable(.lowAccuracy)), [expected])
    }

    /// 責務: 一時停止の複数の判定は報告の配列の順のまま写ることを確かめます。
    func testStopsKeepReportOrder() {
        let later = StopJudgement(passage: Judgement.stopPassage(startedAt: 50, reachedAt: 55), verdict: .stopped)
        let earlier = StopJudgement(passage: Judgement.stopPassage(startedAt: 1, reachedAt: 3), verdict: .notStopped(minimumKph: 9))

        let mapped = entries(of: Fixtures.report(stops: [later, earlier]))

        XCTAssertEqual(mapped.map(\.outcome), [.compliant, .possibleIssue])
        XCTAssertEqual(mapped.map(\.start.time), [50, 1])
    }
}

import Foundation
import XCTest
@testable import ProjectZD8

/// 判定の報告を解析の照合結果へ写す Mapper の、最高速度の写しと報告全体の受け渡しを検証します(設計書 §3.6・§7 TC2)。
///
/// 一時停止・一方通行・徐行の写しは `RoadRegulationSessionReviewMapperOtherKindsTests` で検証します。
/// 期待する文言キーは、設計書の表の文字列リテラルで書きます。
@MainActor
final class RoadRegulationSessionReviewMapperTests: XCTestCase {
    private typealias Fixtures = RoadRegulationSessionReviewMapperFixtures
    private typealias Judgement = RoadRegulationJudgementFixtures

    /// 責務: 報告を既定の Mapper で写します。
    /// - Parameters:
    ///   - report: 判定の報告。
    ///   - usedOn: 利用日。
    /// - Returns: 照合結果。
    private func map(_ report: SessionRoadRegulationReport, usedOn: Date? = Fixtures.usedOn) -> SessionRoadRegulationReview {
        RoadRegulationSessionReviewMapper().review(from: report, usedOn: usedOn, sourceURL: Fixtures.sourceURL)
    }

    /// 責務: 最高速度の判定1件を写した entry を返します。
    /// - Parameters:
    ///   - limitKph: 判定の制限速度。
    ///   - verdict: 判定の値。
    /// - Returns: 写した entry の一覧。
    private func mapSpeedLimit(limitKph: Int?, verdict: SpeedLimitVerdict) -> [SessionRoadRegulationReviewEntry] {
        let traversal = Fixtures.speedLimitTraversal(from: 10, to: 40, sequences: 3...9)
        let judgement = SpeedLimitJudgement(traversal: traversal, limitKph: limitKph, verdict: verdict)
        return map(Fixtures.report(speedLimit: [judgement])).entries
    }

    /// 責務: 制限内は compliant で、制限速度と最高速度を数値に持つことを確かめます。
    func testWithinLimitIsCompliantWithLimitAndMaximum() {
        let entries = mapSpeedLimit(limitKph: 40, verdict: .withinLimit(maxKph: 38.5))

        let expected = Fixtures.entry(
            .speedLimit, .compliant, key: "road_regulation.verdict.speed_limit.within_limit",
            start: Judgement.mark(at: 10, sequence: 3), end: Judgement.mark(at: 40, sequence: 9),
            figures: SessionRoadRegulationReviewFigures(limitKph: 40, maximumKph: 38.5)
        )
        XCTAssertEqual(entries, [expected])
    }

    /// 責務: 超過は possibleIssue で、制限速度・最高速度・超過秒数を数値に持つことを確かめます。
    func testExceededIsPossibleIssueWithExceededSeconds() {
        let entries = mapSpeedLimit(limitKph: 40, verdict: .exceeded(maxKph: 52.3, exceededSeconds: 6.5))

        let expected = Fixtures.entry(
            .speedLimit, .possibleIssue, key: "road_regulation.verdict.speed_limit.exceeded",
            start: Judgement.mark(at: 10, sequence: 3), end: Judgement.mark(at: 40, sequence: 9),
            figures: SessionRoadRegulationReviewFigures(limitKph: 40, maximumKph: 52.3, exceededSeconds: 6.5)
        )
        XCTAssertEqual(entries, [expected])
    }

    /// 責務: 指定なしは unregulated で、数値は判定の制限速度(nil)だけであることを確かめます。
    func testUnregulatedIsUnregulatedWithoutFigures() {
        let entries = mapSpeedLimit(limitKph: nil, verdict: .unregulated)

        let expected = Fixtures.entry(
            .speedLimit, .unregulated, key: "road_regulation.verdict.speed_limit.unregulated",
            start: Judgement.mark(at: 10, sequence: 3), end: Judgement.mark(at: 40, sequence: 9)
        )
        XCTAssertEqual(entries, [expected])
    }

    /// 責務: 判定できない時は undeterminable で、理由と理由のキー、制限速度を持つことを確かめます。
    func testUndeterminableCarriesReasonKeyAndLimit() {
        let entries = mapSpeedLimit(limitKph: 40, verdict: .undeterminable(.speedUnavailable))

        let expected = Fixtures.entry(
            .speedLimit, .undeterminable, key: "road_regulation.undetermined.speed_unavailable", reason: .speedUnavailable,
            start: Judgement.mark(at: 10, sequence: 3), end: Judgement.mark(at: 40, sequence: 9),
            figures: SessionRoadRegulationReviewFigures(limitKph: 40)
        )
        XCTAssertEqual(entries, [expected])
    }

    /// 責務: 判定できない理由が別の値でも、その理由のキーになることを確かめます。
    func testUndeterminableUsesGivenReason() {
        let entries = mapSpeedLimit(limitKph: nil, verdict: .undeterminable(.outsideRegulationData))

        XCTAssertEqual(entries.map(\.verdictKey), ["road_regulation.undetermined.outside_regulation_data"])
        XCTAssertEqual(entries.map(\.undeterminedReason), [.outsideRegulationData])
        XCTAssertEqual(entries.map(\.figures), [SessionRoadRegulationReviewFigures()])
    }

    /// 責務: 同じ種類の判定は報告の配列の順のまま写ることを確かめます(時刻が後の判定を先に置く)。
    func testEntriesKeepReportOrderWithinKind() {
        let laterTraversal = Fixtures.speedLimitTraversal(from: 100, to: 120, sequences: 50...60)
        let earlierTraversal = Fixtures.speedLimitTraversal(from: 0, to: 20, sequences: 0...10)
        let later = SpeedLimitJudgement(traversal: laterTraversal, limitKph: 40, verdict: .withinLimit(maxKph: 30))
        let earlier = SpeedLimitJudgement(traversal: earlierTraversal, limitKph: 40, verdict: .unregulated)

        let entries = map(Fixtures.report(speedLimit: [later, earlier])).entries

        XCTAssertEqual(entries.map(\.outcome), [.compliant, .unregulated])
        XCTAssertEqual(entries.map(\.start.sequence), [50, 0])
    }

    /// 責務: 4種類の判定が1件ずつ entry になり、集計(tally)を使わないことを確かめます。
    func testOneEntryPerJudgementAcrossKinds() {
        let speedTraversal = Fixtures.speedLimitTraversal(from: 0, to: 5, sequences: 0...5)
        let oneWayTraversal = Fixtures.oneWayTraversal(from: 10, to: 15, sequences: 10...15)
        let slowTraversal = Fixtures.slowDownTraversal(from: 16, to: 20, sequences: 16...20)
        let report = Fixtures.report(
            speedLimit: [SpeedLimitJudgement(traversal: speedTraversal, limitKph: 40, verdict: .unregulated)],
            stops: [StopJudgement(passage: Judgement.stopPassage(startedAt: 6, reachedAt: 9), verdict: .stopped)],
            oneWay: [OneWayJudgement(traversal: oneWayTraversal, verdict: .followedDirection)],
            slowDown: [SlowDownJudgement(traversal: slowTraversal, verdict: .observed(maxKph: 9, referenceKph: 10))]
        )

        let entries = map(report).entries

        XCTAssertEqual(entries.map(\.kind), [.speedLimit, .stop, .oneWay, .slowDown])
    }

    /// 責務: 種類をまたぐ並びは 最高速度 → 一時停止 → 一方通行 → 徐行 の連結で、時刻の順に並べ替えないことを確かめます。
    func testKindsAreConcatenatedInFixedOrderRegardlessOfTime() {
        let slowTraversal = Fixtures.slowDownTraversal(from: 0, to: 5, sequences: 0...5)
        let oneWayTraversal = Fixtures.oneWayTraversal(from: 6, to: 9, sequences: 6...9)
        let speedTraversal = Fixtures.speedLimitTraversal(from: 200, to: 220, sequences: 200...220)
        let report = Fixtures.report(
            speedLimit: [SpeedLimitJudgement(traversal: speedTraversal, limitKph: 40, verdict: .withinLimit(maxKph: 30))],
            stops: [StopJudgement(passage: Judgement.stopPassage(startedAt: 100, reachedAt: 110), verdict: .stopped)],
            oneWay: [OneWayJudgement(traversal: oneWayTraversal, verdict: .followedDirection)],
            slowDown: [SlowDownJudgement(traversal: slowTraversal, verdict: .undeterminable(.lowAccuracy))]
        )

        let entries = map(report).entries

        XCTAssertEqual(entries.map(\.kind), [.speedLimit, .stop, .oneWay, .slowDown])
        XCTAssertEqual(entries.map(\.start.time), [200, 100, 6, 0])
    }

    /// 責務: 指定なしでも、判定が制限値を持っていればそれを数値に入れることを確かめます(理由は nil)。
    func testUnregulatedCarriesJudgementLimitWhenPresent() {
        let entries = mapSpeedLimit(limitKph: 30, verdict: .unregulated)

        XCTAssertEqual(entries.map(\.figures), [SessionRoadRegulationReviewFigures(limitKph: 30)])
        XCTAssertEqual(entries.map(\.undeterminedReason), [nil])
    }

    /// 責務: 車速の有無と使った版が報告の範囲から、利用日と配布ページの URL が引数からそのまま渡ることを確かめます。
    func testCoverageUsedOnAndSourceURLArePassedThrough() {
        let datasets = [Fixtures.reference(47, 2026, 9), Fixtures.reference(13, 2026, 8)]

        let review = map(Fixtures.report(hasVehicleSpeed: false, datasets: datasets))

        XCTAssertFalse(review.hasVehicleSpeed)
        XCTAssertEqual(review.datasets, datasets)
        XCTAssertEqual(review.usedOn, Fixtures.usedOn)
        XCTAssertEqual(review.sourceURL, Fixtures.sourceURL)
    }

    /// 責務: 車速あり・利用日なしもそのまま渡ることを確かめます。
    func testVehicleSpeedTrueAndNilUsedOnArePassedThrough() {
        let review = map(Fixtures.report(hasVehicleSpeed: true, datasets: []), usedOn: nil)

        XCTAssertTrue(review.hasVehicleSpeed)
        XCTAssertEqual(review.datasets, [])
        XCTAssertNil(review.usedOn)
    }

    /// 責務: 全配列が空の報告は entry が空になることを確かめます。
    func testEmptyReportHasNoEntries() {
        let review = map(Fixtures.report())

        XCTAssertEqual(review.entries, [])
    }
}

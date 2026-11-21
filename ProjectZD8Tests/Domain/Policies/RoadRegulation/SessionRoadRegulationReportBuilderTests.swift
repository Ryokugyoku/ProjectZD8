import XCTest
@testable import ProjectZD8

/// `SessionRoadRegulationReportBuilder` が、判定を渡された順のまま持ち、種類ごとに件数・判定の値ごとの件数・
/// 「判定できない」の件数と理由ごとの内訳を集計すること(設計書 §3.6 集計)を検証します。
///
/// `verdictCounts` のキーは判定の case 名(`undeterminable` を含む)で、件数0のキーと理由は辞書に入れません。
@MainActor
final class SessionRoadRegulationReportBuilderTests: XCTestCase {
    private typealias Fixtures = RoadRegulationJudgementFixtures
    private let builder = SessionRoadRegulationReportBuilder()

    /// 責務: 版の参照を1つ持つ入力の範囲を作ります。
    private func coverage() throws -> RoadRegulationEvaluationCoverage {
        let reference = RoadRegulationDatasetReference(
            prefecture: try XCTUnwrap(JapanesePrefectureCode(47)),
            dataMonth: try XCTUnwrap(RoadRegulationDataMonth(year: 2026, month: 10))
        )
        return RoadRegulationEvaluationCoverage(
            timeAxis: .monotonic,
            trackPointCount: 120,
            droppedPointCount: 3,
            hasVehicleSpeed: true,
            datasets: [reference]
        )
    }

    /// 責務: 判定の値だけを変えた最高速度の判定を作ります。
    private func speedLimit(_ verdict: SpeedLimitVerdict) -> SpeedLimitJudgement {
        SpeedLimitJudgement(traversal: Fixtures.speedLimitTraversal(limitKph: 40, from: 0, to: 20), limitKph: 40, verdict: verdict)
    }

    /// 責務: 判定の値だけを変えた一時停止の判定を作ります。
    private func stop(_ verdict: StopVerdict) -> StopJudgement {
        StopJudgement(passage: Fixtures.stopPassage(startedAt: 10, reachedAt: 14), verdict: verdict)
    }

    /// 責務: 判定の値だけを変えた一方通行の判定を作ります。
    private func oneWay(_ verdict: OneWayVerdict) -> OneWayJudgement {
        OneWayJudgement(traversal: Fixtures.traversal(.oneWay(.on(Fixtures.regulationID, .reverse)), from: 0, to: 20), verdict: verdict)
    }

    /// 責務: 判定の値だけを変えた徐行の判定を作ります。
    private func slowDown(_ verdict: SlowDownVerdict) -> SlowDownJudgement {
        SlowDownJudgement(traversal: Fixtures.traversal(.slowDown(.on(Fixtures.regulationID)), from: 0, to: 20), verdict: verdict)
    }

    /// 責務: 判定が1件も無ければ、4種類とも件数0・内訳なしになり、入力の範囲はそのまま入ることを確かめます。
    func testEmptyInputProducesZeroTallies() throws {
        let coverage = try coverage()
        let report = builder.build(speedLimit: [], stops: [], oneWay: [], slowDown: [], coverage: coverage)
        XCTAssertEqual(report.coverage, coverage)
        XCTAssertTrue(report.speedLimit.isEmpty && report.stops.isEmpty && report.oneWay.isEmpty && report.slowDown.isEmpty)
        for tally in [report.speedLimitTally, report.stopTally, report.oneWayTally, report.slowDownTally] {
            XCTAssertEqual(tally.total, 0)
            XCTAssertEqual(tally.undetermined, 0)
            XCTAssertEqual(tally.verdictCounts, [:])
            XCTAssertEqual(tally.undeterminedByReason, [:])
        }
    }

    /// 責務: 最高速度の集計が、判定できなかった件数を総数に含め、値ごと・理由ごとに数えることを確かめます。
    func testSpeedLimitTallyCountsVerdictsAndReasons() throws {
        let judgements = [
            speedLimit(.withinLimit(maxKph: 42)), speedLimit(.undeterminable(.speedUnavailable)),
            speedLimit(.exceeded(maxKph: 50, exceededSeconds: 3)), speedLimit(.withinLimit(maxKph: 38)),
            speedLimit(.unregulated), speedLimit(.undeterminable(.possiblyDifferentRoad)),
            speedLimit(.undeterminable(.speedUnavailable))
        ]
        let tally = builder.build(speedLimit: judgements, stops: [], oneWay: [], slowDown: [], coverage: try coverage()).speedLimitTally
        XCTAssertEqual(tally.total, 7)
        XCTAssertEqual(tally.undetermined, 3)
        XCTAssertEqual(tally.verdictCounts, ["withinLimit": 2, "exceeded": 1, "unregulated": 1, "undeterminable": 3])
        XCTAssertEqual(tally.undeterminedByReason, [.speedUnavailable: 2, .possiblyDifferentRoad: 1])
    }

    /// 責務: 一時停止の集計が、停止・停止していない・判定できない(理由ごと)を数えることを確かめます。
    func testStopTallyCountsVerdictsAndReasons() throws {
        let judgements = [
            stop(.stopped), stop(.notStopped(minimumKph: 10)), stop(.undeterminable(.trackGap)),
            stop(.notStopped(minimumKph: 12)), stop(.undeterminable(.conditionUnknown))
        ]
        let tally = builder.build(speedLimit: [], stops: judgements, oneWay: [], slowDown: [], coverage: try coverage()).stopTally
        XCTAssertEqual(tally.total, 5)
        XCTAssertEqual(tally.undetermined, 2)
        XCTAssertEqual(tally.verdictCounts, ["stopped": 1, "notStopped": 2, "undeterminable": 2])
        XCTAssertEqual(tally.undeterminedByReason, [.trackGap: 1, .conditionUnknown: 1])
    }

    /// 責務: 一方通行の集計が、向きどおり・逆走の可能性・判定できない(理由ごと)を数えることを確かめます。
    func testOneWayTallyCountsVerdictsAndReasons() throws {
        let judgements = [
            oneWay(.followedDirection), oneWay(.possibleWrongWay(distanceMeters: 100)), oneWay(.undeterminable(.insufficientDistance)),
            oneWay(.undeterminable(.lowAccuracy)), oneWay(.undeterminable(.insufficientDistance))
        ]
        let tally = builder.build(speedLimit: [], stops: [], oneWay: judgements, slowDown: [], coverage: try coverage()).oneWayTally
        XCTAssertEqual(tally.total, 5)
        XCTAssertEqual(tally.undetermined, 3)
        XCTAssertEqual(tally.verdictCounts, ["followedDirection": 1, "possibleWrongWay": 1, "undeterminable": 3])
        XCTAssertEqual(tally.undeterminedByReason, [.insufficientDistance: 2, .lowAccuracy: 1])
    }

    /// 責務: 徐行の集計が、観測した件数と判定できない(理由ごと)を数えることを確かめます。
    func testSlowDownTallyCountsVerdictsAndReasons() throws {
        let judgements = [
            slowDown(.observed(maxKph: 14, referenceKph: 10)), slowDown(.undeterminable(.speedUnavailable)),
            slowDown(.observed(maxKph: 8, referenceKph: 10))
        ]
        let tally = builder.build(speedLimit: [], stops: [], oneWay: [], slowDown: judgements, coverage: try coverage()).slowDownTally
        XCTAssertEqual(tally.total, 3)
        XCTAssertEqual(tally.undetermined, 1)
        XCTAssertEqual(tally.verdictCounts, ["observed": 2, "undeterminable": 1])
        XCTAssertEqual(tally.undeterminedByReason, [.speedUnavailable: 1])
    }

    /// 責務: すべて判定できなかった時も、総数と判定できない件数が一致して数えられる(0 に潰れない)ことを確かめます。
    func testAllUndeterminedAreStillCounted() throws {
        let judgements = [stop(.undeterminable(.speedSamplingTooSparse)), stop(.undeterminable(.speedSamplingTooSparse))]
        let tally = builder.build(speedLimit: [], stops: judgements, oneWay: [], slowDown: [], coverage: try coverage()).stopTally
        XCTAssertEqual(tally.total, 2)
        XCTAssertEqual(tally.undetermined, 2)
        XCTAssertEqual(tally.verdictCounts, ["undeterminable": 2])
        XCTAssertEqual(tally.undeterminedByReason, [.speedSamplingTooSparse: 2])
    }

    /// 責務: 判定を渡された順のまま持ち、種類ごとの集計がほかの種類の判定を混ぜないことを確かめます。
    func testJudgementsKeepOrderAndTalliesStaySeparate() throws {
        let speeds = [speedLimit(.exceeded(maxKph: 50, exceededSeconds: 3)), speedLimit(.withinLimit(maxKph: 42))]
        let stops = [stop(.undeterminable(.trackGap))]
        let oneWays = [oneWay(.followedDirection), oneWay(.possibleWrongWay(distanceMeters: 60))]
        let slowDowns = [slowDown(.observed(maxKph: 9, referenceKph: 10))]
        let report = builder.build(speedLimit: speeds, stops: stops, oneWay: oneWays, slowDown: slowDowns, coverage: try coverage())
        XCTAssertEqual(report.speedLimit, speeds)
        XCTAssertEqual(report.stops, stops)
        XCTAssertEqual(report.oneWay, oneWays)
        XCTAssertEqual(report.slowDown, slowDowns)
        XCTAssertEqual([report.speedLimitTally.total, report.stopTally.total, report.oneWayTally.total, report.slowDownTally.total], [2, 1, 2, 1])
        XCTAssertEqual(
            [report.speedLimitTally.undetermined, report.stopTally.undetermined, report.oneWayTally.undetermined, report.slowDownTally.undetermined],
            [0, 1, 0, 0]
        )
        XCTAssertEqual(report.speedLimitTally.verdictCounts, ["exceeded": 1, "withinLimit": 1])
        XCTAssertEqual(report.speedLimitTally.undeterminedByReason, [:])
        XCTAssertEqual(report.stopTally.undeterminedByReason, [.trackGap: 1])
    }
}

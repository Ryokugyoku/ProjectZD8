import XCTest
@testable import ProjectZD8

/// `StopJudge` が、一時停止の通過を設計書 §3.6(一時停止)どおりに判定することを検証します。
///
/// 通過はすべて「開始 10 s・到達 14 s」です。停止の証拠の窓 E は [9, 15](`stopEvidenceMarginSeconds` = 1)です。
@MainActor
final class StopJudgeTests: XCTestCase {
    private typealias Fixtures = RoadRegulationJudgementFixtures
    private let standard = RoadRegulationMatchingThresholds.standard

    /// 責務: 開始 10 s・到達 14 s の通過を、指定のしきい値で判定します。
    private func verdict(
        _ samples: [(TimeInterval, Double)],
        applicability: RegulationApplicability = .applies,
        interruptedByGap: Bool = false,
        thresholds: RoadRegulationMatchingThresholds = .standard
    ) -> StopVerdict {
        let passage = Fixtures.stopPassage(startedAt: 10, reachedAt: 14, applicability: applicability, interruptedByGap: interruptedByGap)
        return StopJudge(thresholds: thresholds).judge(passage, speeds: Fixtures.timeline(samples)).verdict
    }

    /// 責務: 判定結果が渡した通過をそのまま持つことを確かめます。
    func testJudgementKeepsPassage() {
        let passage = Fixtures.stopPassage(startedAt: 10, reachedAt: 14)
        XCTAssertEqual(StopJudge(thresholds: standard).judge(passage, speeds: Fixtures.timeline([])).passage, passage)
    }

    /// 責務: 記録の空白で到達扱いにした通過は、車速に停止があっても「記録の途切れ」で判定できないことを確かめます。
    func testInterruptedPassageIsTrackGap() {
        XCTAssertEqual(verdict(Fixtures.steady(0, over: 8...16), interruptedByGap: true), .undeterminable(.trackGap))
    }

    /// 責務: 条件が「当てはまる」以外(不明・当てはまらない)の通過は、車速に停止があっても「条件不明」で判定できないことを確かめます。
    func testNonApplyingApplicabilityIsConditionUnknown() {
        XCTAssertEqual(verdict(Fixtures.steady(0, over: 8...16), applicability: .unknown), .undeterminable(.conditionUnknown))
        XCTAssertEqual(verdict(Fixtures.steady(0, over: 8...16), applicability: .doesNotApply), .undeterminable(.conditionUnknown))
    }

    /// 責務: 車速の時系列が空なら「車速なし」で判定できないことを確かめます。
    func testEmptyTimelineIsSpeedUnavailable() {
        XCTAssertEqual(verdict([]), .undeterminable(.speedUnavailable))
    }

    /// 責務: 接近の途中に 0 km/h のサンプルがあれば停止したと判定することを確かめます。
    func testZeroSpeedDuringApproachIsStopped() {
        let samples = Fixtures.steady(20, over: 8...11) + [(12, 0)] + Fixtures.steady(20, over: 13...16)
        XCTAssertEqual(verdict(samples), .stopped)
    }

    /// 責務: 停止の証拠の窓 E = [開始 − 1, 到達 + 1] の両端ちょうどのサンプルを数え、車速 0.5 ちょうどを停止とみなすことを確かめます。
    func testEvidenceWindowEdgesAndStoppedSpeedBoundary() {
        XCTAssertEqual(verdict([(9, standard.stoppedSpeedKph)] + Fixtures.steady(30, over: 10...14)), .stopped)
        XCTAssertEqual(verdict(Fixtures.steady(30, over: 10...14) + [(15, 0)]), .stopped)
    }

    /// 責務: E の外(8.99 s と 15.01 s)の 0 km/h は停止の証拠にならず、区間の車速から「停止していない」になることを確かめます。
    ///
    /// B は開始・到達ちょうどのサンプルで閉じ、30 km/h・1 s 間隔は必要な時間 (30 + 30) / 3.6 / 5 = 3.33 s より短いです。
    func testZeroSpeedOutsideEvidenceWindowIsIgnored() {
        let samples = [(8.99, 0.0)] + Fixtures.steady(30, over: 10...14) + [(15.01, 0.0)]
        XCTAssertEqual(verdict(samples), .notStopped(minimumKph: 30))
    }

    /// 責務: 0.5 を少し超える 0.6 km/h は停止とみなさず、1 s 間隔では短い停止を消せないので判定できないことを確かめます。
    func testSpeedJustAboveStoppedThresholdIsNotStopped() {
        XCTAssertEqual(verdict(Fixtures.steady(0.6, over: 8...16)), .undeterminable(.speedSamplingTooSparse))
    }

    /// 責務: 10 km/h が 1 s 間隔で続けば、必要な時間 1.11 s より短いので「停止していない(最低 10)」になることを確かめます。
    func testTenKphAtOneSecondIntervalIsNotStopped() {
        XCTAssertEqual(verdict(Fixtures.steady(10, over: 8...16)), .notStopped(minimumKph: 10))
    }

    /// 責務: 5 km/h が 1 s 間隔で続けば、必要な時間 0.556 s 以上空いているので判定できないことを確かめます。
    func testFiveKphAtOneSecondIntervalIsTooSparse() {
        XCTAssertEqual(verdict(Fixtures.steady(5, over: 8...16)), .undeterminable(.speedSamplingTooSparse))
    }

    /// 責務: 必要な時間の境目の前後(9.5 km/h → 1.056 s、8.5 km/h → 0.944 s。間隔 1 s)で結果が分かれることを確かめます。
    func testRequiredIntervalBoundaryAroundOneSecond() {
        XCTAssertEqual(verdict(Fixtures.steady(9.5, over: 8...16)), .notStopped(minimumKph: 9.5))
        XCTAssertEqual(verdict(Fixtures.steady(8.5, over: 8...16)), .undeterminable(.speedSamplingTooSparse))
    }

    /// 責務: 開始前・到達後のサンプルが 3 s ちょうど離れていれば判定でき、3.01 s 離れていれば判定できないことを確かめます。
    ///
    /// 60 km/h の必要な時間は (60 + 60) / 3.6 / 5 = 6.67 s で、間隔 4 s は短い停止の可能性に当たりません。
    func testBracketSampleDistanceBoundary() {
        let inside = Fixtures.steady(60, over: 11...13)
        XCTAssertEqual(verdict([(7, 60)] + inside + [(17, 60)]), .notStopped(minimumKph: 60))
        XCTAssertEqual(verdict([(6.99, 60)] + inside + [(17, 60)]), .undeterminable(.speedSamplingTooSparse))
        XCTAssertEqual(verdict([(7, 60)] + inside + [(17.01, 60)]), .undeterminable(.speedSamplingTooSparse))
        XCTAssertEqual(verdict(inside + [(17, 60)]), .undeterminable(.speedSamplingTooSparse), "開始以前のサンプルが無い")
        XCTAssertEqual(verdict([(7, 60)] + inside), .undeterminable(.speedSamplingTooSparse), "到達以後のサンプルが無い")
    }

    /// 責務: 「停止していない」の最低車速に、開始前と到達後のサンプルも含めることを確かめます。
    func testMinimumIncludesBracketSamples() {
        let samples: [(TimeInterval, Double)] = [(9, 20), (10.5, 30), (11.5, 30), (12.5, 30), (13.5, 30), (14.5, 25)]
        XCTAssertEqual(verdict(samples), .notStopped(minimumKph: 20))
    }

    /// 責務: 最大の減速度を 10 m/s² にすると、標準では「停止していない」の 10 km/h・1 s 間隔が判定できないになることを確かめます。
    func testCustomDecelerationChangesVerdict() {
        var custom = standard
        custom.maximumDecelerationMps2 = 10
        XCTAssertEqual(verdict(Fixtures.steady(10, over: 8...16), thresholds: custom), .undeterminable(.speedSamplingTooSparse))
    }

    /// 責務: 停止の車速・証拠の窓の幅・前後の間隔の上限を変えると、判定がその値に従うことを確かめます。
    func testCustomStopThresholdsChangeVerdict() {
        var stoppedSpeed = standard
        stoppedSpeed.stoppedSpeedKph = 1
        XCTAssertEqual(verdict(Fixtures.steady(0.6, over: 8...16), thresholds: stoppedSpeed), .stopped)

        var margin = standard
        margin.stopEvidenceMarginSeconds = 2
        XCTAssertEqual(verdict([(8.5, 0.0)] + Fixtures.steady(30, over: 10...14), thresholds: margin), .stopped)

        var bracket = standard
        bracket.stopBracketMaximumSeconds = 2
        let samples = [(7.0, 60.0)] + Fixtures.steady(60, over: 11...13) + [(17.0, 60.0)]
        XCTAssertEqual(verdict(samples, thresholds: bracket), .undeterminable(.speedSamplingTooSparse))
    }
}

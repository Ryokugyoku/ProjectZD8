import XCTest
@testable import ProjectZD8

/// `SpeedLimitJudge` が、区間の状態の扱いと、超過の連続(設計書 §3.6 最高速度)を仕様どおりに判定することを検証します。
///
/// 取得間隔の粗さと、しきい値の差し替えは `SpeedLimitJudgeSamplingTests` で扱います。
@MainActor
final class SpeedLimitJudgeTests: XCTestCase {
    private typealias Fixtures = RoadRegulationJudgementFixtures
    private let thresholds = RoadRegulationMatchingThresholds.standard

    /// 責務: 制限速度 `limitKph`・窓 [from, to] の区間を、標準のしきい値で判定します。
    private func judge(limitKph: Int, from: TimeInterval = 0, to: TimeInterval = 20, _ samples: [(TimeInterval, Double)]) -> SpeedLimitJudgement {
        SpeedLimitJudge(thresholds: thresholds)
            .judge(Fixtures.speedLimitTraversal(limitKph: limitKph, from: from, to: to), speeds: Fixtures.timeline(samples))
    }

    /// 責務: 判定できない区間が、どの理由でもその理由のまま判定できないになり、制限値を持たないことを確かめます。
    func testUndeterminableStatusKeepsItsReason() {
        let speeds = Fixtures.timeline(Fixtures.steady(90, over: 0...20))
        for reason in RoadRegulationUndeterminedReason.allCases {
            let traversal = Fixtures.traversal(.speedLimit(.undeterminable(reason, Fixtures.regulationID)), from: 0, to: 20)
            let judgement = SpeedLimitJudge(thresholds: thresholds).judge(traversal, speeds: speeds)
            XCTAssertEqual(judgement.verdict, .undeterminable(reason), "\(reason)")
            XCTAssertNil(judgement.limitKph, "\(reason)")
            XCTAssertEqual(judgement.traversal, traversal, "\(reason)")
        }
    }

    /// 責務: 規制の適用が「不明」の区間(状態 `conditionUnknown`)が、車速によらず判定できないになることを確かめます。
    func testConditionUnknownIsUndeterminableEvenWithoutSpeed() {
        let traversal = Fixtures.traversal(.speedLimit(.undeterminable(.conditionUnknown, nil)), from: 0, to: 20)
        let judgement = SpeedLimitJudge(thresholds: thresholds).judge(traversal, speeds: Fixtures.timeline([]))
        XCTAssertEqual(judgement.verdict, .undeterminable(.conditionUnknown))
    }

    /// 責務: 指定なしの区間(条件が当てはまらない規制は候補から外れてこうなる)が、速い車速でも判定の対象外になることを確かめます。
    func testUnregulatedStatusIsNotJudged() {
        let traversal = Fixtures.traversal(.speedLimit(.unregulated), from: 0, to: 20)
        let judgement = SpeedLimitJudge(thresholds: thresholds).judge(traversal, speeds: Fixtures.timeline(Fixtures.steady(120, over: 0...20)))
        XCTAssertEqual(judgement.verdict, .unregulated)
        XCTAssertNil(judgement.limitKph)
    }

    /// 責務: 記録器が出さないはずの確定待ち(`pending`)の区間が、成功に潰れず「記録の途切れ」で判定できないになることを確かめます。
    func testPendingStatusIsTrackGap() {
        let traversal = Fixtures.traversal(.speedLimit(.pending), from: 0, to: 20)
        let judgement = SpeedLimitJudge(thresholds: thresholds).judge(traversal, speeds: Fixtures.timeline(Fixtures.steady(40, over: 0...20)))
        XCTAssertEqual(judgement.verdict, .undeterminable(.trackGap))
        XCTAssertNil(judgement.limitKph)
    }

    /// 責務: 開始と終了が逆順の区間でも、窓 [min, max] の両端を含めて判定することを確かめます。
    func testReversedWindowIsNormalized() {
        let traversal = Fixtures.speedLimitTraversal(limitKph: 40, from: 20, to: 10)
        let samples = [(9.0, 120.0)] + Fixtures.steady(30, over: 10...19) + [(20.0, 42.0), (21.0, 120.0)]
        let judgement = SpeedLimitJudge(thresholds: thresholds).judge(traversal, speeds: Fixtures.timeline(samples))
        XCTAssertEqual(judgement.verdict, .withinLimit(maxKph: 42))
    }

    /// 責務: 規制区間で車速の時系列がまったく無ければ「車速なし」で判定できず、制限値は残ることを確かめます。
    func testRegulatedWithoutAnySpeedIsSpeedUnavailable() {
        let judgement = judge(limitKph: 40, [])
        XCTAssertEqual(judgement.verdict, .undeterminable(.speedUnavailable))
        XCTAssertEqual(judgement.limitKph, 40)
    }

    /// 責務: L=40(許容3)で、42 と 43(= 制限 + 許容ちょうど)が 1 Hz で続いても制限内になることを確かめます。
    func testSteadySpeedUpToLimitPlusToleranceIsWithinLimit() {
        XCTAssertEqual(thresholds.speedTolerance(limitKph: 40), 3)
        XCTAssertEqual(judge(limitKph: 40, Fixtures.steady(42, over: 0...20)).verdict, .withinLimit(maxKph: 42))
        XCTAssertEqual(judge(limitKph: 40, Fixtures.steady(43, over: 0...20)).verdict, .withinLimit(maxKph: 43))
    }

    /// 責務: L=40 で 44 が t = 10, 11, 12(2秒)続くと、超過(最高 44・2秒)になることを確かめます。
    func testExceedRunOfMinimumDurationIsExceeded() {
        let samples = Fixtures.steady(40, over: 0...9) + Fixtures.steady(44, over: 10...12) + Fixtures.steady(40, over: 13...20)
        let judgement = judge(limitKph: 40, samples)
        XCTAssertEqual(judgement.verdict, .exceeded(maxKph: 44, exceededSeconds: thresholds.minimumExceedDurationSeconds))
        XCTAssertEqual(judgement.limitKph, 40)
    }

    /// 責務: 超過が2秒に満たない(1点だけ・1秒だけ)時は、超過でなく制限内(窓の最高)になることを確かめます。
    func testExceedShorterThanMinimumDurationIsWithinLimit() {
        let single = Fixtures.steady(40, over: 0...9) + [(10, 44)] + Fixtures.steady(40, over: 11...20)
        XCTAssertEqual(judge(limitKph: 40, single).verdict, .withinLimit(maxKph: 44))
        let oneSecond = Fixtures.steady(40, over: 0...9) + Fixtures.steady(44, over: 10...11) + Fixtures.steady(40, over: 12...20)
        XCTAssertEqual(judge(limitKph: 40, oneSecond).verdict, .withinLimit(maxKph: 44))
    }

    /// 責務: 間に制限内のサンプルが挟まると超過の連続が切れることを確かめます(44, 40, 44 は連続にならない)。
    func testWithinLimitSampleBreaksExceedRun() {
        let samples = Fixtures.steady(40, over: 0...9) + [(10, 44), (11, 40), (12, 44)] + Fixtures.steady(40, over: 13...20)
        XCTAssertEqual(judge(limitKph: 40, samples).verdict, .withinLimit(maxKph: 44))
    }

    /// 責務: L=80(許容4)で、84 は制限内、85 は超過になることを確かめます。
    func testLimit80UsesToleranceOfFour() {
        XCTAssertEqual(thresholds.speedTolerance(limitKph: 80), 4)
        XCTAssertEqual(judge(limitKph: 80, Fixtures.steady(84, over: 0...20)).verdict, .withinLimit(maxKph: 84))
        XCTAssertEqual(judge(limitKph: 80, Fixtures.steady(85, over: 0...20)).verdict, .exceeded(maxKph: 85, exceededSeconds: 20))
    }

    /// 責務: 超過のサンプルの間隔が 3 s(`maximumExceedRunGapSeconds`)ちょうどなら連続とみなし、3.01 s なら連続にならないことを確かめます。
    func testExceedRunGapBoundary() {
        let gap = thresholds.maximumExceedRunGapSeconds
        let joined = Fixtures.steady(40, over: 0...9) + [(10, 44), (10 + gap, 44)] + Fixtures.steady(40, over: 14...20)
        XCTAssertEqual(judge(limitKph: 40, joined).verdict, .exceeded(maxKph: 44, exceededSeconds: gap))
        let split = Fixtures.steady(40, over: 0...9) + [(10, 44), (10 + gap + 0.01, 44)] + Fixtures.steady(40, over: 14...20)
        XCTAssertEqual(judge(limitKph: 40, split).verdict, .withinLimit(maxKph: 44))
    }

    /// 責務: 超過の連続が2つある時、秒数は連続ごとの長さの合計(2 + 3 = 5秒)になり、最高車速は連続の中の最大になることを確かめます。
    func testExceededSecondsAreSummedOverRuns() {
        let samples = Fixtures.steady(40, over: 0...4) + Fixtures.steady(44, over: 5...7) + Fixtures.steady(40, over: 8...19)
            + Fixtures.steady(50, over: 20...23) + Fixtures.steady(40, over: 24...30)
        XCTAssertEqual(judge(limitKph: 40, to: 30, samples).verdict, .exceeded(maxKph: 50, exceededSeconds: 5))
    }

    /// 責務: 超過量(最高車速 − L。許容は引かない)が 40 未満なら超過、40 ちょうど以上なら「別の道路の可能性」になることを確かめます。
    ///
    /// L=40 で 79.9(超過量 39.9)は超過、80(40 ちょうど)と 90 は判定できません。
    func testImplausibleExcessIsPossiblyDifferentRoad() {
        XCTAssertEqual(thresholds.implausibleExcessKph, 40)
        XCTAssertEqual(judge(limitKph: 40, Fixtures.steady(79.9, over: 0...20)).verdict, .exceeded(maxKph: 79.9, exceededSeconds: 20))
        XCTAssertEqual(judge(limitKph: 40, Fixtures.steady(80, over: 0...20)).verdict, .undeterminable(.possiblyDifferentRoad))
        XCTAssertEqual(judge(limitKph: 40, Fixtures.steady(90, over: 0...20)).verdict, .undeterminable(.possiblyDifferentRoad))
    }

    /// 責務: 窓 [10, 20] の外(9 秒と 21 秒)にある速いサンプルを判定に使わないことを確かめます。
    func testSamplesOutsideWindowAreIgnored() {
        let samples = [(9.0, 120.0)] + Fixtures.steady(40, over: 10...20) + [(21.0, 120.0)]
        XCTAssertEqual(judge(limitKph: 40, from: 10, to: 20, samples).verdict, .withinLimit(maxKph: 40))
    }

    /// 責務: 窓の両端ちょうどのサンプルは窓に含まれ、最高車速に数えることを確かめます。
    func testSamplesAtWindowEdgesAreIncluded() {
        let atStart = [(10.0, 42.0)] + Fixtures.steady(30, over: 11...20)
        XCTAssertEqual(judge(limitKph: 40, from: 10, to: 20, atStart).verdict, .withinLimit(maxKph: 42))
        let atEnd = Fixtures.steady(30, over: 10...19) + [(20.0, 42.0)]
        XCTAssertEqual(judge(limitKph: 40, from: 10, to: 20, atEnd).verdict, .withinLimit(maxKph: 42))
    }
}

import XCTest
@testable import ProjectZD8

/// `SpeedLimitJudge` が、車速の取得間隔が粗い時に制限内と言い切らないこと(設計書 §3.6 最高速度)と、
/// 判定がしきい値の値に従うこと(埋め込みの数値でないこと)を検証します。
@MainActor
final class SpeedLimitJudgeSamplingTests: XCTestCase {
    private typealias Fixtures = RoadRegulationJudgementFixtures
    private let standard = RoadRegulationMatchingThresholds.standard

    /// 責務: 制限 40 km/h・窓 [from, to] の区間を、指定のしきい値で判定します。
    private func verdict(
        _ samples: [(TimeInterval, Double)],
        from: TimeInterval = 0,
        to: TimeInterval = 20,
        thresholds: RoadRegulationMatchingThresholds = .standard
    ) -> SpeedLimitVerdict {
        SpeedLimitJudge(thresholds: thresholds)
            .judge(Fixtures.speedLimitTraversal(limitKph: 40, from: from, to: to), speeds: Fixtures.timeline(samples))
            .verdict
    }

    /// 責務: 始まり側の空き(最初のサンプル − 開始)が 5 s ちょうどなら制限内、5.01 s なら取得間隔が粗いことを確かめます。
    func testLeadingGapBoundary() {
        let gap = standard.maximumSpeedSampleGapSeconds
        XCTAssertEqual(verdict(Fixtures.steady(40, over: 5...20)), .withinLimit(maxKph: 40))
        XCTAssertEqual(verdict([(gap + 0.01, 40)] + Fixtures.steady(40, over: 6...20)), .undeterminable(.speedSamplingTooSparse))
    }

    /// 責務: 終わり側の空き(終了 − 最後のサンプル)が 5 s ちょうどなら制限内、5.01 s なら取得間隔が粗いことを確かめます。
    func testTrailingGapBoundary() {
        XCTAssertEqual(verdict(Fixtures.steady(40, over: 0...15)), .withinLimit(maxKph: 40))
        XCTAssertEqual(verdict(Fixtures.steady(40, over: 0...14) + [(14.99, 40)]), .undeterminable(.speedSamplingTooSparse))
    }

    /// 責務: 窓の中のサンプルの間隔が 5 s ちょうどなら制限内、5.01 s なら取得間隔が粗いことを確かめます。
    func testInteriorGapBoundary() {
        XCTAssertEqual(verdict(Fixtures.steady(40, over: 0...5) + Fixtures.steady(40, over: 10...20)), .withinLimit(maxKph: 40))
        let sparse = Fixtures.steady(40, over: 0...5) + [(10.01, 40)] + Fixtures.steady(40, over: 11...20)
        XCTAssertEqual(verdict(sparse), .undeterminable(.speedSamplingTooSparse))
    }

    /// 責務: 時系列はあるが窓の中にサンプルが1つも無ければ、取得間隔が粗いとして判定できないことを確かめます。
    func testEmptyWindowWithSamplesElsewhereIsSparse() {
        let samples = Fixtures.steady(40, over: 0...9) + Fixtures.steady(40, over: 31...40)
        XCTAssertEqual(verdict(samples, from: 10, to: 30), .undeterminable(.speedSamplingTooSparse))
    }

    /// 責務: 取得間隔が粗くても、超過の連続が見つかれば超過になることを確かめます(超過の判定は取得間隔に依存しない)。
    func testExceedRunIsReportedEvenWhenSamplingIsSparse() {
        XCTAssertEqual(verdict(Fixtures.steady(44, over: 10...12), from: 0, to: 30), .exceeded(maxKph: 44, exceededSeconds: 2))
    }

    /// 責務: 取得間隔が粗くても、ありえない超過の連続は「別の道路の可能性」になることを確かめます。
    func testImplausibleExceedRunIsPossiblyDifferentRoadEvenWhenSparse() {
        XCTAssertEqual(verdict(Fixtures.steady(90, over: 10...12), from: 0, to: 30), .undeterminable(.possiblyDifferentRoad))
    }

    /// 責務: 速度の許容の最小値を 10 にすると、標準では超過の 44 が制限内になることを確かめます。
    func testCustomSpeedToleranceChangesExceedBoundary() {
        XCTAssertEqual(verdict(Fixtures.steady(44, over: 0...20)), .exceeded(maxKph: 44, exceededSeconds: 20))
        var custom = standard
        custom.speedToleranceMinimumKph = 10
        XCTAssertEqual(verdict(Fixtures.steady(44, over: 0...20), thresholds: custom), .withinLimit(maxKph: 44))
    }

    /// 責務: 必要な取得間隔を 2 s にすると、標準では制限内の 3 s 間隔が粗いと判定されることを確かめます。
    func testCustomSampleGapChangesSparsity() {
        let samples: [(TimeInterval, Double)] = stride(from: 0, through: 21, by: 3).map { (TimeInterval($0), 40) }
        XCTAssertEqual(verdict(samples, to: 21), .withinLimit(maxKph: 40))
        var custom = standard
        custom.maximumSpeedSampleGapSeconds = 2
        XCTAssertEqual(verdict(samples, to: 21, thresholds: custom), .undeterminable(.speedSamplingTooSparse))
    }

    /// 責務: ありえない超過量を 5 km/h にすると、標準では超過の 50 が「別の道路の可能性」になることを確かめます。
    func testCustomImplausibleExcessChangesVerdict() {
        XCTAssertEqual(verdict(Fixtures.steady(50, over: 0...20)), .exceeded(maxKph: 50, exceededSeconds: 20))
        var custom = standard
        custom.implausibleExcessKph = 5
        XCTAssertEqual(verdict(Fixtures.steady(50, over: 0...20), thresholds: custom), .undeterminable(.possiblyDifferentRoad))
    }

    /// 責務: 超過の最短の長さを 1 s にすると、標準では制限内の「44 が1秒」が超過になることを確かめます。
    func testCustomMinimumExceedDurationChangesVerdict() {
        let samples = Fixtures.steady(40, over: 0...9) + Fixtures.steady(44, over: 10...11) + Fixtures.steady(40, over: 12...20)
        XCTAssertEqual(verdict(samples), .withinLimit(maxKph: 44))
        var custom = standard
        custom.minimumExceedDurationSeconds = 1
        XCTAssertEqual(verdict(samples, thresholds: custom), .exceeded(maxKph: 44, exceededSeconds: 1))
    }
}

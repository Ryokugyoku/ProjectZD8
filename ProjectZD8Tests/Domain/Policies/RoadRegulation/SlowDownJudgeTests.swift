import XCTest
@testable import ProjectZD8

/// `SlowDownJudge` が、徐行の区間に合否を付けず、窓の中の最高車速と参考の速さを返すこと(設計書 §3.6 徐行)を検証します。
@MainActor
final class SlowDownJudgeTests: XCTestCase {
    private typealias Fixtures = RoadRegulationJudgementFixtures
    private let standard = RoadRegulationMatchingThresholds.standard

    /// 責務: 窓 [10, 20] の徐行の区間を、指定のしきい値で判定します。
    private func verdict(_ samples: [(TimeInterval, Double)], thresholds: RoadRegulationMatchingThresholds = .standard) -> SlowDownVerdict {
        let traversal = Fixtures.traversal(.slowDown(.on(Fixtures.regulationID)), from: 10, to: 20)
        return SlowDownJudge(thresholds: thresholds).judge(traversal, speeds: Fixtures.timeline(samples)).verdict
    }

    /// 責務: 窓の中の最高車速が 14 なら、参考の速さ 10 とともに `observed(14, 10)` になることを確かめます(超えていても合否は付けない)。
    func testMaximumSpeedIsObservedWithReference() {
        XCTAssertEqual(standard.slowDownReferenceKph, 10)
        XCTAssertEqual(verdict([(11, 8), (13, 14), (16, 12)]), .observed(maxKph: 14, referenceKph: 10))
    }

    /// 責務: 判定結果が渡した区間をそのまま持つことを確かめます。
    func testJudgementKeepsTraversal() {
        let traversal = Fixtures.traversal(.slowDown(.on(Fixtures.regulationID)), from: 10, to: 20)
        XCTAssertEqual(SlowDownJudge(thresholds: standard).judge(traversal, speeds: Fixtures.timeline([(12, 5)])).traversal, traversal)
    }

    /// 責務: 窓の両端ちょうどのサンプルは数え、窓のすぐ外(9.99 s と 20.01 s)のサンプルは数えないことを確かめます。
    func testWindowIsInclusiveAndIgnoresOutsideSamples() {
        XCTAssertEqual(verdict([(9.99, 60), (10, 12), (15, 6), (20.01, 60)]), .observed(maxKph: 12, referenceKph: 10))
        XCTAssertEqual(verdict([(9.99, 60), (15, 6), (20, 13), (20.01, 60)]), .observed(maxKph: 13, referenceKph: 10))
    }

    /// 責務: 開始と終了が逆順の区間でも、窓 [min, max] の両端を含めて最高車速を返すことを確かめます。
    func testReversedWindowIsNormalized() {
        let traversal = Fixtures.traversal(.slowDown(.on(Fixtures.regulationID)), from: 20, to: 10)
        let speeds = Fixtures.timeline([(9.99, 60), (10, 11), (15, 6), (20, 7), (20.01, 60)])
        XCTAssertEqual(SlowDownJudge(thresholds: standard).judge(traversal, speeds: speeds).verdict, .observed(maxKph: 11, referenceKph: 10))
    }

    /// 責務: 窓の中にサンプルが1つだけでも、その車速を返すことを確かめます。
    func testSingleSampleInWindowIsObserved() {
        XCTAssertEqual(verdict([(15, 4)]), .observed(maxKph: 4, referenceKph: 10))
    }

    /// 責務: 車速の時系列が空なら「車速なし」で判定できないことを確かめます。
    func testEmptyTimelineIsSpeedUnavailable() {
        XCTAssertEqual(verdict([]), .undeterminable(.speedUnavailable))
    }

    /// 責務: 時系列はあるが窓の中にサンプルが無ければ、取得間隔が粗いとして判定できないことを確かめます。
    func testEmptyWindowWithSamplesElsewhereIsSparse() {
        XCTAssertEqual(verdict([(9.99, 8), (20.01, 8)]), .undeterminable(.speedSamplingTooSparse))
    }

    /// 責務: 参考の速さを 20 にすると、返す参考の速さがその値になることを確かめます。
    func testCustomReferenceSpeedIsReturned() {
        var custom = standard
        custom.slowDownReferenceKph = 20
        XCTAssertEqual(verdict([(11, 8), (13, 14), (16, 12)], thresholds: custom), .observed(maxKph: 14, referenceKph: 20))
    }
}

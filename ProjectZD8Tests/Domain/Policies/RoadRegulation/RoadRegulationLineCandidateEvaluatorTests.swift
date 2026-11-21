import XCTest
@testable import ProjectZD8

/// `RoadRegulationLineCandidateEvaluator` が、線までの距離を横方向の許容(設計書 §3.2: clamp(12 + 精度, 15, 35) m、
/// いま乗っている候補は +10 m)で絞ることを検証します(§3.5 の 2、TB2)。
///
/// 道は南北の線 (x, −200)–(x, 200)(方位 0 度・長さ 400 m)で、点は (d, 0) に置くので、横方向の距離は d m です。
/// 境界はちょうどの値を避け、許容の ±0.5 m で確かめます。
@MainActor
final class RoadRegulationLineCandidateEvaluatorTests: XCTestCase {
    private typealias Shapes = RoadRegulationMeterRegulationFactory
    private typealias Points = RoadRegulationMeterTrackPointFactory

    /// 責務: 東へ x m の南北の線(最高速度の区間)を作ります。
    private func northRoad(id: Int64, x: Double = 0) -> RoadRegulation {
        Shapes.line(id: id, points: [(x: x, y: -200), (x: x, y: 200)])
    }

    /// 責務: 点 (x, y)・精度・向きで候補を評価します(向きを区別しない)。
    private func matches(
        x: Double,
        y: Double = 0,
        accuracy: Double = 0,
        heading: Double? = nil,
        candidates: [RoadRegulation],
        current: Int64? = nil,
        thresholds: RoadRegulationMatchingThresholds = .standard
    ) -> [RoadRegulationLineMatch] {
        RoadRegulationLineCandidateEvaluator(thresholds: thresholds).matches(
            point: Points.point(x: x, y: y, accuracy: accuracy),
            heading: heading,
            candidates: candidates,
            mode: .directionAgnostic,
            currentRegulationID: current.map { RoadRegulationID(rawValue: $0) }
        )
    }

    /// 責務: 候補の id を返します。
    private func ids(_ matches: [RoadRegulationLineMatch]) -> [Int64] {
        matches.map(\.regulation.id.rawValue)
    }

    /// 責務: 候補が空なら結果も空であることを確かめます。
    func testEmptyCandidatesGiveNoMatches() {
        XCTAssertEqual(matches(x: 0, candidates: []), [])
    }

    /// 責務: 線から 4 m の点(向きなし)の結果が、距離 4・角度差なし・進む向きなし・点数 4・粗くない・除外に近くないことを確かめます。
    func testMatchCarriesDistanceAndPlainFlags() throws {
        let road = northRoad(id: 1)
        let match = try XCTUnwrap(matches(x: 4, candidates: [road]).first)
        XCTAssertEqual(match.regulation, road)
        XCTAssertEqual(match.distanceMeters, 4, accuracy: 0.01)
        XCTAssertNil(match.headingDifference)
        XCTAssertNil(match.travelDirection)
        XCTAssertEqual(match.score, 4, accuracy: 0.01)
        XCTAssertFalse(match.isCoarse)
        XCTAssertFalse(match.isNearExclusion)
    }

    /// 責務: 精度 0 の許容は 15 m(12 + 0 = 12 を最小 15 へ切り上げ)で、14.5 m は入り 15.5 m は入らないことを確かめます。
    func testToleranceAtZeroAccuracyIsMinimum() {
        XCTAssertEqual(ids(matches(x: 14.5, accuracy: 0, candidates: [northRoad(id: 1)])), [1])
        XCTAssertEqual(ids(matches(x: 15.5, accuracy: 0, candidates: [northRoad(id: 1)])), [])
    }

    /// 責務: 精度 2 の許容は 12 + 2 = 14 でなく最小の 15 m で、14.5 m は入り 15.5 m は入らないことを確かめます。
    func testToleranceIsClampedToMinimum() {
        XCTAssertEqual(ids(matches(x: 14.5, accuracy: 2, candidates: [northRoad(id: 1)])), [1])
        XCTAssertEqual(ids(matches(x: 15.5, accuracy: 2, candidates: [northRoad(id: 1)])), [])
    }

    /// 責務: 精度 10 の許容は 12 + 10 = 22 m で、21.5 m は入り 22.5 m は入らないことを確かめます。
    func testToleranceGrowsWithAccuracy() {
        XCTAssertEqual(ids(matches(x: -21.5, accuracy: 10, candidates: [northRoad(id: 1)])), [1])
        XCTAssertEqual(ids(matches(x: -22.5, accuracy: 10, candidates: [northRoad(id: 1)])), [])
    }

    /// 責務: 精度 30 の許容は 12 + 30 = 42 でなく最大の 35 m で、34.5 m は入り 35.5 m は入らないことを確かめます。
    func testToleranceIsClampedToMaximum() {
        XCTAssertEqual(ids(matches(x: 34.5, accuracy: 30, candidates: [northRoad(id: 1)])), [1])
        XCTAssertEqual(ids(matches(x: 35.5, accuracy: 30, candidates: [northRoad(id: 1)])), [])
    }

    /// 責務: いま乗っている候補は許容 + 10 m(精度 0 なら 25 m)まで残り、ほかの候補は 15 m で外れることを確かめます。
    func testCurrentRegulationKeepsExtraHysteresis() {
        XCTAssertEqual(ids(matches(x: 24.5, candidates: [northRoad(id: 1)], current: 1)), [1])
        XCTAssertEqual(ids(matches(x: 24.5, candidates: [northRoad(id: 1)], current: 2)), [])
        XCTAssertEqual(ids(matches(x: 24.5, candidates: [northRoad(id: 1)])), [])
        XCTAssertEqual(ids(matches(x: 25.5, candidates: [northRoad(id: 1)], current: 1)), [])
    }

    /// 責務: いま乗っている候補の残す幅を 20 m に変えると 34.5 m でも残ることを確かめます(埋め込みの数値でない)。
    func testHysteresisIsConfigurable() {
        var thresholds = RoadRegulationMatchingThresholds.standard
        thresholds.exitHysteresisMeters = 20
        XCTAssertEqual(ids(matches(x: 34.5, candidates: [northRoad(id: 1)], current: 1, thresholds: thresholds)), [1])
    }

    /// 責務: 許容の基本値を 20 m に変えると、精度 0 の許容が 20 m になり 19.5 m が入ることを確かめます(埋め込みの数値でない)。
    func testToleranceBaseIsConfigurable() {
        var thresholds = RoadRegulationMatchingThresholds.standard
        thresholds.lateralToleranceBaseMeters = 20
        XCTAssertEqual(ids(matches(x: 19.5, candidates: [northRoad(id: 1)], thresholds: thresholds)), [1])
        XCTAssertEqual(ids(matches(x: 20.5, candidates: [northRoad(id: 1)], thresholds: thresholds)), [])
    }

    /// 責務: 線の端 (0, 200) の外側では端までの距離で測ることを確かめます(北へ 10 m → 10、(6, 208) → 10、北へ 15.5 m → 入らない)。
    func testBeyondLineEndUsesDistanceToEndpoint() throws {
        let road = northRoad(id: 1)
        let ahead = try XCTUnwrap(matches(x: 0, y: 210, candidates: [road]).first)
        XCTAssertEqual(ahead.distanceMeters, 10, accuracy: 0.01)
        let diagonal = try XCTUnwrap(matches(x: 6, y: 208, candidates: [road]).first)
        XCTAssertEqual(diagonal.distanceMeters, 10, accuracy: 0.01)
        XCTAssertEqual(ids(matches(x: 0, y: 215.5, candidates: [road])), [])
    }

    /// 責務: 近い候補だけを残し、許容の外の候補を落とすことを確かめます。
    func testOnlyCandidatesWithinToleranceRemain() {
        let near = northRoad(id: 1, x: 3)
        let far = northRoad(id: 2, x: 60)
        XCTAssertEqual(ids(matches(x: 0, candidates: [far, near])), [1])
    }
}

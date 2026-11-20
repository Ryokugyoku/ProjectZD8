import XCTest
@testable import ProjectZD8

/// `RoadRegulationLineCandidateEvaluator` の点数と並び順、粗い線分、除外の形状の近さを検証します(設計書 §3.5 の 2・3、TB2)。
///
/// 点数 = 距離 + 0.2 × 角度差 − (いま乗っている候補なら 5)。結果は点数の昇順です。線分の長さが 1,000 m を超えれば `isCoarse`。
/// 点は原点・精度 5(許容 17 m)で、道は南北の線 (x, −200)–(x, 200)(方位 0 度)です。
@MainActor
final class RoadRegulationLineCandidateEvaluatorScoreTests: XCTestCase {
    private typealias Shapes = RoadRegulationMeterRegulationFactory
    private typealias Points = RoadRegulationMeterTrackPointFactory

    /// 責務: 東へ x m の南北の線を作ります。
    private func northRoad(id: Int64, x: Double, exclusion: [(x: Double, y: Double)]? = nil) -> RoadRegulation {
        Shapes.line(id: id, points: [(x: x, y: -200), (x: x, y: 200)], exclusion: exclusion)
    }

    /// 責務: 点 (x, y)・精度 5 で候補を評価します(向きを区別しない)。
    private func matches(
        _ candidates: [RoadRegulation],
        heading: Double?,
        x: Double = 0,
        y: Double = 0,
        current: Int64? = nil,
        thresholds: RoadRegulationMatchingThresholds = .standard
    ) -> [RoadRegulationLineMatch] {
        RoadRegulationLineCandidateEvaluator(thresholds: thresholds).matches(
            point: Points.point(x: x, y: y, accuracy: 5),
            heading: heading,
            candidates: candidates,
            mode: .directionAgnostic,
            currentRegulationID: current.map { RoadRegulationID(rawValue: $0) }
        )
    }

    /// 責務: 結果の id と点数が期待どおり(点数は 0.01 以内)であることを確かめます。
    private func assertRanking(
        _ matches: [RoadRegulationLineMatch],
        _ expected: [(id: Int64, score: Double)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(matches.map(\.regulation.id.rawValue), expected.map(\.id), file: file, line: line)
        for (match, want) in zip(matches, expected) {
            XCTAssertEqual(match.score, want.score, accuracy: 0.01, "id \(want.id)", file: file, line: line)
        }
    }

    /// 責務: 点数の昇順に並ぶことを確かめます(西 4 m → 4 + 0.2 × 10 = 6、東 8 m → 8 + 2 = 10。id の順とは逆)。
    func testMatchesAreSortedByScore() {
        assertRanking(matches([northRoad(id: 1, x: 8), northRoad(id: 2, x: -4)], heading: 10), [(2, 6), (1, 10)])
    }

    /// 責務: いま乗っている候補の点数から 5 を引き、順位が入れ替わることを確かめます(東 8 m → 10 − 5 = 5、西 4 m → 6)。
    func testCurrentRegulationBonusReordersMatches() {
        assertRanking(matches([northRoad(id: 1, x: 8), northRoad(id: 2, x: -4)], heading: 10, current: 1), [(1, 5), (2, 6)])
    }

    /// 責務: 点数の差が曖昧の幅(3 m)より小さい2件も、大きい2件も、どちらも点数順のまま返すことを確かめます
    /// (曖昧かどうかは経路の側で決めるため、ここでは落とさない)。
    func testCloseAndDistantCandidatesAreBothReturned() {
        assertRanking(matches([northRoad(id: 1, x: 5), northRoad(id: 2, x: -4)], heading: nil), [(2, 4), (1, 5)])
        assertRanking(matches([northRoad(id: 1, x: 14), northRoad(id: 2, x: -2)], heading: nil), [(2, 2), (1, 14)])
    }

    /// 責務: 角度差1度あたりの不利を 1 m に変えると点数が 4 + 1 × 10 = 14 になることを確かめます(埋め込みの数値でない)。
    func testHeadingPenaltyIsConfigurable() {
        var thresholds = RoadRegulationMatchingThresholds.standard
        thresholds.headingPenaltyMetersPerDegree = 1
        assertRanking(matches([northRoad(id: 1, x: 4)], heading: 10, thresholds: thresholds), [(1, 14)])
    }

    /// 責務: いま乗っている候補の有利を 2 m に変えると点数が 4 − 2 = 2 になることを確かめます(埋め込みの数値でない)。
    func testCurrentBonusIsConfigurable() {
        var thresholds = RoadRegulationMatchingThresholds.standard
        thresholds.currentRegulationBonusMeters = 2
        assertRanking(matches([northRoad(id: 1, x: 4)], heading: nil, current: 1, thresholds: thresholds), [(1, 2)])
    }

    /// 責務: 長さ 3,000 m の1本の線分に近い点の結果が `isCoarse` になることを確かめます。
    func testLongSegmentIsCoarse() throws {
        let coarse = Shapes.line(id: 1, points: [(x: 5, y: -1_500), (x: 5, y: 1_500)])
        XCTAssertTrue(try XCTUnwrap(matches([coarse], heading: 0).first).isCoarse)
    }

    /// 責務: 粗さの境界(1,000 m)の少し内の 999 m は粗くなく、少し外の 1,001 m は粗いことを確かめます。
    func testCoarseLengthBoundary() throws {
        let shorter = Shapes.line(id: 1, points: [(x: 5, y: -499.5), (x: 5, y: 499.5)])
        let longer = Shapes.line(id: 2, points: [(x: 5, y: -500.5), (x: 5, y: 500.5)])
        XCTAssertFalse(try XCTUnwrap(matches([shorter], heading: 0).first).isCoarse)
        XCTAssertTrue(try XCTUnwrap(matches([longer], heading: 0).first).isCoarse)
    }

    /// 責務: 折れ線では最も近い線分の長さで粗さを決めることを確かめます(200 m の線分の近くは粗くなく、2,000 m の線分の近くは粗い)。
    func testCoarsenessFollowsNearestSegment() throws {
        let road = Shapes.line(id: 1, points: [(x: 0, y: -100), (x: 0, y: 100), (x: 0, y: 2_100)])
        XCTAssertFalse(try XCTUnwrap(matches([road], heading: 0, x: 5, y: 0).first).isCoarse)
        XCTAssertTrue(try XCTUnwrap(matches([road], heading: 0, x: 5, y: 1_000).first).isCoarse)
    }

    /// 責務: 粗いとみなす長さを 300 m に変えると 400 m の線分が粗くなることを確かめます(埋め込みの数値でない)。
    func testCoarseLengthIsConfigurable() throws {
        var thresholds = RoadRegulationMatchingThresholds.standard
        thresholds.coarseSegmentLengthMeters = 300
        XCTAssertTrue(try XCTUnwrap(matches([northRoad(id: 1, x: 5)], heading: 0, thresholds: thresholds).first).isCoarse)
        XCTAssertFalse(try XCTUnwrap(matches([northRoad(id: 1, x: 5)], heading: 0).first).isCoarse)
    }

    /// 責務: 同じ点数の候補は id の昇順に並ぶことを確かめます(東西 4 m の2本、向きなし → どちらも 4)。
    func testTiedScoresAreOrderedByID() {
        assertRanking(matches([northRoad(id: 2, x: -4), northRoad(id: 1, x: 4)], heading: nil), [(1, 4), (2, 4)])
    }

    /// 責務: 粗い線分は横方向の許容(17 m)でなく `coarseCorridorMeters`(100 m)で当てはまり、いま乗っていても +10 m しないことを確かめます。
    ///
    /// 長さ 3,000 m の線から 50 m → 当てはまる、99.5 m → 当てはまる、100.5 m → いま乗っている候補でも当てはまらない。
    func testCoarseSegmentUsesCorridor() throws {
        let coarse = Shapes.line(id: 1, points: [(x: 0, y: -1_500), (x: 0, y: 1_500)])
        let fifty = try XCTUnwrap(matches([coarse], heading: 0, x: 50).first)
        XCTAssertTrue(fifty.isCoarse)
        XCTAssertEqual(fifty.distanceMeters, 50, accuracy: 0.01)
        XCTAssertEqual(matches([coarse], heading: 0, x: 99.5).count, 1)
        XCTAssertEqual(matches([coarse], heading: 0, x: 100.5), [])
        XCTAssertEqual(matches([coarse], heading: 0, x: 100.5, current: 1), [])
    }

    /// 責務: 粗くない線分が当てはまれば、それより近い粗い線分があっても粗くない方を採ることを確かめます。
    ///
    /// 線 (0, −100)–(0, 100)–(0, 2,100) で点 (5, 110): 粗くない1本目の端まで √(25 + 100) ≈ 11.18 m(許容 17 m 以内)、
    /// 粗い2本目まで 5 m。結果は粗くない・距離 11.18 です。
    func testNonCoarseSegmentIsPreferredWhenItMatches() throws {
        let road = Shapes.line(id: 1, points: [(x: 0, y: -100), (x: 0, y: 100), (x: 0, y: 2_100)])
        let match = try XCTUnwrap(matches([road], heading: 0, x: 5, y: 110).first)
        XCTAssertFalse(match.isCoarse)
        XCTAssertEqual(match.distanceMeters, 125.0.squareRoot(), accuracy: 0.01)
    }

    /// 責務: 粗い線分でも、向きが分かっていて合わない(90 度)なら候補にしないことを確かめます。
    func testCoarseSegmentWithMisalignedHeadingIsExcluded() {
        let coarse = Shapes.line(id: 1, points: [(x: 5, y: -1_500), (x: 5, y: 1_500)])
        XCTAssertEqual(matches([coarse], heading: 90), [])
    }

    /// 責務: 点から 3 m に除外区間がある候補は `isNearExclusion` になり、約 150 m 離れた除外区間や除外の無い候補はならないことを確かめます。
    func testExclusionNearnessUsesTolerance() throws {
        let nearExclusion = northRoad(id: 1, x: 0, exclusion: [(x: 0, y: -10), (x: 0, y: 10)])
        let farExclusion = northRoad(id: 2, x: 0, exclusion: [(x: 0, y: 150), (x: 0, y: 190)])
        XCTAssertTrue(try XCTUnwrap(matches([nearExclusion], heading: 0, x: 3).first).isNearExclusion)
        XCTAssertFalse(try XCTUnwrap(matches([farExclusion], heading: 0, x: 3).first).isNearExclusion)
        XCTAssertFalse(try XCTUnwrap(matches([northRoad(id: 3, x: 0)], heading: 0, x: 3).first).isNearExclusion)
    }
}

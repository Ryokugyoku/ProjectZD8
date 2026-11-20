import XCTest
@testable import ProjectZD8

/// `DrivingRouteSegmenter` の時間差と位置の飛びによる区切りを、設計書 §2.1・§9 T3-1 で検証します。
@MainActor
final class DrivingRouteSegmenterGapTests: XCTestCase {
    private typealias Fixtures = DrivingRouteTrackFixtures
    private let segmenter = DrivingRouteSegmenter()
    private let reducedAccuracyEvent = Fixtures.event(0, at: -100, .recordingWithReducedAccuracy)

    /// 責務: 2点を指定の時間差・距離で置き、区間の連番を返します。
    private func shape(gap: TimeInterval, meters: Double = 0, events: [ConnectionSessionLocationEvent] = []) -> [[Int64]] {
        let samples = [Fixtures.sample(0, at: 0), Fixtures.sample(1, at: gap, x: meters)]
        return Fixtures.sequences(of: segmenter.route(from: Fixtures.track(samples, events: events)))
    }

    /// 責務: 正確な位置の時間差 10.0 s ちょうどが、つながることを確かめます。
    func testPreciseGapOfExactlyTenSecondsIsConnected() {
        XCTAssertEqual(shape(gap: 10.0), [[0, 1]])
    }

    /// 責務: 正確な位置の時間差が 10 s を少しでも超えると、切ることを確かめます。
    func testPreciseGapJustOverTenSecondsCuts() {
        XCTAssertEqual(shape(gap: 10.001), [[0], [1]])
    }

    /// 責務: 正確な位置の時間差が 10 s の少し内側なら、つながることを確かめます。
    func testPreciseGapJustUnderTenSecondsIsConnected() {
        XCTAssertEqual(shape(gap: 9.999), [[0, 1]])
    }

    /// 責務: 概略の位置の時間差 1,200.0 s ちょうどが、つながることを確かめます。
    func testApproximateGapOfExactly1200SecondsIsConnected() {
        XCTAssertEqual(shape(gap: 1_200.0, events: [reducedAccuracyEvent]), [[0, 1]])
    }

    /// 責務: 概略の位置の時間差が 1,200 s を少しでも超えると、切ることを確かめます。
    func testApproximateGapJustOver1200SecondsCuts() {
        XCTAssertEqual(shape(gap: 1_200.001, events: [reducedAccuracyEvent]), [[0], [1]])
    }

    /// 責務: 概略の位置だけの間は粗いしきい値を使い、100 s の差でもつなぐ(正確なら切る)ことを確かめます。
    func testApproximateUsesCoarserThresholdThanPrecise() {
        XCTAssertEqual(shape(gap: 100, events: [reducedAccuracyEvent]), [[0, 1]])
        XCTAssertEqual(shape(gap: 100), [[0], [1]])
    }

    /// 責務: 推定の速さが 90 m/s の少し内側(10 s で 880 m)なら、つなぐことを確かめます。
    func testImpliedSpeedJustUnderLimitIsConnected() {
        XCTAssertEqual(shape(gap: 10, meters: 880), [[0, 1]])
    }

    /// 責務: 推定の速さが 90 m/s の少し外側(10 s で 920 m)なら、位置の飛びとして切ることを確かめます。
    func testImpliedSpeedJustOverLimitCuts() {
        XCTAssertEqual(shape(gap: 10, meters: 920), [[0], [1]])
    }

    /// 責務: あり得ない距離(1 s で 5 km)の飛びで切り、前後の点はそれぞれの区間に残ることを確かめます。
    func testImpossibleJumpCutsAndKeepsBothPoints() {
        let samples = [
            Fixtures.sample(0, at: 0),
            Fixtures.sample(1, at: 1),
            Fixtures.sample(2, at: 2, x: 5_000),
            Fixtures.sample(3, at: 3, x: 5_001)
        ]
        let route = segmenter.route(from: Fixtures.track(samples))
        XCTAssertEqual(Fixtures.sequences(of: route), [[0, 1], [2, 3]])
        XCTAssertEqual(route.excludedFixCount, 0)
    }

    /// 責務: 概略の位置でも、速さの上限(100 s で 8,900 m は内側、9,100 m は外側)を使うことを確かめます。
    func testApproximateStageAlsoChecksImpliedSpeed() {
        XCTAssertEqual(shape(gap: 100, meters: 8_900, events: [reducedAccuracyEvent]), [[0, 1]])
        XCTAssertEqual(shape(gap: 100, meters: 9_100, events: [reducedAccuracyEvent]), [[0], [1]])
    }

    /// 責務: 3点のうち、2番目と3番目の間だけが長く空いた時、そこだけで切ることを確かめます。
    func testOnlyTheLargeGapIsCut() {
        let samples = [Fixtures.sample(0, at: 0), Fixtures.sample(1, at: 5), Fixtures.sample(2, at: 20)]
        let route = segmenter.route(from: Fixtures.track(samples))
        XCTAssertEqual(Fixtures.sequences(of: route), [[0, 1], [2]])
    }
}

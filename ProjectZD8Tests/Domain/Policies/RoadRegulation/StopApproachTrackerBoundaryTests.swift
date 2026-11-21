import XCTest
@testable import ProjectZD8

/// `StopApproachTracker` の開始と到達の境界を検証します(設計書 §3.2・§3.5、TB6)。
///
/// S は原点、E は南へ 15 m(s = 北への距離 y、l = |x|、方位(E → S)= 0 度)。
/// - 開始: −40 ≤ s < −5、l ≤ 許容、角度差(h, 0) ≤ 45。許容 = clamp(8 + 精度, 10, 20)。
/// - 到達: 接近中に s ≥ −5 かつ l ≤ 許容 + 10。
/// 境界はちょうどの値を避け、±0.5 m・±1 度で確かめます。
@MainActor
final class StopApproachTrackerBoundaryTests: XCTestCase {
    private typealias Driver = StopApproachTrackerTestDriver
    private typealias Shapes = RoadRegulationMeterRegulationFactory
    private typealias Points = RoadRegulationMeterTrackPointFactory

    /// 進入方向 0 の鍵。
    private let key = StopApproachKey(regulationID: RoadRegulationID(rawValue: 10), approachIndex: 0)

    /// 責務: S が原点・E が南へ 15 m の一時停止を候補に持つ駆動役を返します。
    private func driver(_ thresholds: RoadRegulationMatchingThresholds = .standard) -> Driver {
        var driver = Driver(candidates: [Shapes.stop(id: 10, at: (x: 0, y: 0), approaches: [(x: 0, y: -15)])])
        driver.thresholds = thresholds
        return driver
    }

    /// 責務: 1点だけの経路で開始が出るかを返します。
    private func starts(x: Double, y: Double, heading: Double?, accuracy: Double = 5, thresholds: RoadRegulationMatchingThresholds = .standard) -> Bool {
        let changes = driver(thresholds).changes([(x: x, y: y, heading: heading, accuracy: accuracy)])
        if changes == [.stopApproachStarted(key, Points.mark(0))] { return true }
        XCTAssertEqual(changes, [], "開始以外の変化が出ました")
        return false
    }

    /// 責務: 開始の手前側の境界(s = −40)の少し内の −39.5 で開始し、少し外の −40.5 で開始しないことを確かめます。
    func testStartWindowFarEdge() {
        XCTAssertTrue(starts(x: 0, y: -39.5, heading: 0))
        XCTAssertFalse(starts(x: 0, y: -40.5, heading: 0))
    }

    /// 責務: 開始の停止点側の境界(s < −5)の少し手前の −5.5 で開始し、−4.5 では開始しないことを確かめます。
    func testStartWindowNearEdge() {
        XCTAssertTrue(starts(x: 0, y: -5.5, heading: 0))
        XCTAssertFalse(starts(x: 0, y: -4.5, heading: 0))
    }

    /// 責務: 精度 5 の許容 13 m の少し内(l = 12.5)で開始し、少し外(13.5)で開始しないことを確かめます(西側も同じ)。
    func testStartLateralToleranceWithAccuracyFive() {
        XCTAssertTrue(starts(x: 12.5, y: -20, heading: 0))
        XCTAssertTrue(starts(x: -12.5, y: -20, heading: 0))
        XCTAssertFalse(starts(x: 13.5, y: -20, heading: 0))
    }

    /// 責務: 精度 0 の許容は 8 + 0 = 8 でなく最小の 10 m で、9.5 m で開始し 10.5 m で開始しないことを確かめます。
    func testStartLateralToleranceIsClampedToMinimum() {
        XCTAssertTrue(starts(x: 9.5, y: -20, heading: 0, accuracy: 0))
        XCTAssertFalse(starts(x: 10.5, y: -20, heading: 0, accuracy: 0))
    }

    /// 責務: 精度 20 の許容は 8 + 20 = 28 でなく最大の 20 m で、19.5 m で開始し 20.5 m で開始しないことを確かめます。
    func testStartLateralToleranceIsClampedToMaximum() {
        XCTAssertTrue(starts(x: 19.5, y: -20, heading: 0, accuracy: 20))
        XCTAssertFalse(starts(x: 20.5, y: -20, heading: 0, accuracy: 20))
    }

    /// 責務: 開始の角度差の境界(45 度)の少し内の 44 度・316 度で開始し、46 度・314 度と向き不明では開始しないことを確かめます。
    func testStartHeadingBoundaryAndUnknownHeading() {
        XCTAssertTrue(starts(x: 0, y: -20, heading: 44))
        XCTAssertTrue(starts(x: 0, y: -20, heading: 316))
        XCTAssertFalse(starts(x: 0, y: -20, heading: 46))
        XCTAssertFalse(starts(x: 0, y: -20, heading: 314))
        XCTAssertFalse(starts(x: 0, y: -20, heading: nil))
    }

    /// 責務: 到達の境界(s ≥ −5)の少し手前の −5.5 では到達せず、−4.5 で到達することを確かめます。
    func testReachBoundary() {
        let path = Driver.straight(x: 0, ys: [-38, -5.5, -4.5], heading: 0)
        XCTAssertEqual(driver().changes(path), [
            .stopApproachStarted(key, Points.mark(0)),
            .stopReached(StopPassage(
                key: key, approachStarted: Points.mark(0), reached: Points.mark(2), applicability: .applies, interruptedByGap: false
            )),
        ])
    }

    /// 責務: 到達の横方向の許容は 許容 + 10 = 23 m(精度 5)で、22.5 m 横でも到達することを確かめます。
    func testReachAllowsLateralTolerancePlusExtra() {
        let path: [Driver.PathPoint] = [(x: 0, y: -38, heading: 0, accuracy: 5), (x: 22.5, y: -3, heading: 0, accuracy: 5)]
        XCTAssertEqual(driver().changes(path), [
            .stopApproachStarted(key, Points.mark(0)),
            .stopReached(StopPassage(
                key: key, approachStarted: Points.mark(0), reached: Points.mark(1), applicability: .applies, interruptedByGap: false
            )),
        ])
    }

    /// 責務: 停止点の手前で接近を追う長さを 30 m に縮めると、s = −35 では開始しないことを確かめます(埋め込みの数値でない)。
    func testApproachLengthIsConfigurable() {
        var thresholds = RoadRegulationMatchingThresholds.standard
        thresholds.stopApproachLengthMeters = 30
        XCTAssertFalse(starts(x: 0, y: -35, heading: 0, thresholds: thresholds))
        XCTAssertTrue(starts(x: 0, y: -35, heading: 0))
    }

    /// 責務: 開始の角度差を 30 度に下げると 40 度では開始しないことを確かめます(埋め込みの数値でない)。
    func testStartHeadingIsConfigurable() {
        var thresholds = RoadRegulationMatchingThresholds.standard
        thresholds.stopHeadingDegrees = 30
        XCTAssertFalse(starts(x: 0, y: -20, heading: 40, thresholds: thresholds))
        XCTAssertTrue(starts(x: 0, y: -20, heading: 40))
    }
}

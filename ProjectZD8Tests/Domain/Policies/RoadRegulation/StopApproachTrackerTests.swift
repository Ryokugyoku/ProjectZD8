import XCTest
@testable import ProjectZD8

/// `StopApproachTracker` が、停止点 S への接近の開始・到達・打ち切りを設計書 §3.5(一時停止)どおりに出すことを、
/// 代表的な走り方で検証します(TB6)。
///
/// S は原点、進入方向の点 E は南へ 15 m です。u = (S − E) の単位ベクトル = 北、s = (P − S)·u = 北への距離 y、l = |x|。
/// 精度 5 の許容は clamp(8 + 5, 10, 20) = 13 m、方位(E → S)は 0 度です。開始は −40 ≤ s < −5、到達は s ≥ −5。
/// 経路は 5 m 刻みで、ちょうどの境界を避けるため y = −58, −53, … とします(開始は y = −38、到達は y = −3)。
@MainActor
final class StopApproachTrackerTests: XCTestCase {
    private typealias Driver = StopApproachTrackerTestDriver
    private typealias Shapes = RoadRegulationMeterRegulationFactory
    private typealias Points = RoadRegulationMeterTrackPointFactory

    /// 一時停止の規制の行 ID。
    private let stopID = RoadRegulationID(rawValue: 10)

    /// 責務: S が原点・E が南へ 15 m の一時停止を返します。
    private func southApproachStop() -> RoadRegulation {
        Shapes.stop(id: 10, at: (x: 0, y: 0), approaches: [(x: 0, y: -15)])
    }

    /// 責務: 進入方向の添字 `index` の鍵を返します。
    private func key(_ index: Int) -> StopApproachKey {
        StopApproachKey(regulationID: stopID, approachIndex: index)
    }

    /// 責務: 開始と到達の連番から、空白でない通過を返します。
    private func passage(_ index: Int, started: Int64, reached: Int64, applicability: RegulationApplicability = .applies) -> StopPassage {
        StopPassage(
            key: key(index),
            approachStarted: Points.mark(started),
            reached: Points.mark(reached),
            applicability: applicability,
            interruptedByGap: false
        )
    }

    /// 責務: y = −58 から +22 まで北向き(0 度)に 5 m 刻みで進む経路を返します(添字 4 が y = −38、添字 11 が y = −3)。
    private func northboundPath(x: Double = 0) -> [Driver.PathPoint] {
        Driver.straight(x: x, ys: Driver.values(from: -58, through: 22, by: 5), heading: 0)
    }

    /// 責務: 北向きに通り抜けると、y = −38 で開始、y = −3 で到達が各1回だけ出ることを確かめます。
    func testNorthboundPassEmitsOneStartAndOneReach() {
        let changes = Driver(candidates: [southApproachStop()]).changes(northboundPath())
        XCTAssertEqual(changes, [
            .stopApproachStarted(key(0), Points.mark(4)),
            .stopReached(passage(0, started: 4, reached: 11)),
        ])
    }

    /// 責務: 到達した後、S から 60 m 以内で止まったり動いたりしても、再び開始も到達も出ないことを確かめます。
    func testStayingNearStopAfterReachDoesNotCountAgain() {
        let path = Driver.straight(x: 0, ys: [-38, -3, -4, -2, -4, -3], heading: 0)
        let changes = Driver(candidates: [southApproachStop()]).changes(path)
        XCTAssertEqual(changes, [
            .stopApproachStarted(key(0), Points.mark(0)),
            .stopReached(passage(0, started: 0, reached: 1)),
        ])
    }

    /// 責務: 逆向き(南向き 180 度)に通り抜けると何も出ないことを確かめます。
    func testSouthboundPassEmitsNothing() {
        let path = Driver.straight(x: 0, ys: Driver.values(from: 58, through: -58, by: -5), heading: 180)
        XCTAssertEqual(Driver(candidates: [southApproachStop()]).changes(path), [])
    }

    /// 責務: 進入方向の手前を横切る向き(東向き 90 度、y = −20)で通ると何も出ないことを確かめます。
    func testCrossingTrafficEmitsNothing() {
        let path = Driver.values(from: -58, through: 22, by: 5).map { (x: $0, y: -20.0, heading: Double?(90), accuracy: 5.0) }
        XCTAssertEqual(Driver(candidates: [southApproachStop()]).changes(path), [])
    }

    /// 責務: 東へ 25 m ずれた平行な道を北向きに走ると(l = 25 > 許容 13)何も出ないことを確かめます。
    func testParallelRoadOffsetBeyondToleranceEmitsNothing() {
        XCTAssertEqual(Driver(candidates: [southApproachStop()]).changes(northboundPath(x: 25)), [])
    }

    /// 責務: 接近の途中で右へ曲がる(向き 95 度。角度差 95 > 90)と打ち切りが出て、到達は出ないことを確かめます。
    func testTurningAwayDuringApproachAbandons() {
        let path: [Driver.PathPoint] = [
            (x: 0, y: -38, heading: 0, accuracy: 5),
            (x: 0, y: -28, heading: 0, accuracy: 5),
            (x: 5, y: -25, heading: 95, accuracy: 5),
            (x: 10, y: -25, heading: 95, accuracy: 5),
        ]
        XCTAssertEqual(Driver(candidates: [southApproachStop()]).changes(path), [
            .stopApproachStarted(key(0), Points.mark(0)),
            .stopApproachAbandoned(key(0)),
        ])
    }

    /// 責務: 接近の途中の向きの揺れが 90 度の少し内(85 度)なら打ち切らず、そのまま到達することを確かめます。
    func testHeadingWobbleWithinAbandonLimitStillReaches() {
        let path: [Driver.PathPoint] = [
            (x: 0, y: -38, heading: 0, accuracy: 5),
            (x: 2, y: -25, heading: 85, accuracy: 5),
            (x: 0, y: -3, heading: 0, accuracy: 5),
        ]
        XCTAssertEqual(Driver(candidates: [southApproachStop()]).changes(path), [
            .stopApproachStarted(key(0), Points.mark(0)),
            .stopReached(passage(0, started: 0, reached: 2)),
        ])
    }

    /// 責務: 条件が当てはまらない(`doesNotApply`)一時停止は、北向きに通り抜けても開始しないことを確かめます。
    func testNotApplyingConditionsDoNotStartApproach() {
        var driver = Driver(candidates: [southApproachStop()])
        driver.applicability = .doesNotApply
        XCTAssertEqual(driver.changes(northboundPath()), [])
    }

    /// 責務: 条件が不明(`unknown`)なら接近を追い、通過に `unknown` を添えることを確かめます。
    func testUnknownConditionsAreAttachedToPassage() {
        var driver = Driver(candidates: [southApproachStop()])
        driver.applicability = .unknown
        XCTAssertEqual(driver.changes(northboundPath()), [
            .stopApproachStarted(key(0), Points.mark(4)),
            .stopReached(passage(0, started: 4, reached: 11, applicability: .unknown)),
        ])
    }

    /// 責務: 一時停止でない規制(進入方向の点を持たない線)が候補に混ざっても、一時停止の変化だけが出ることを確かめます。
    func testNonStopCandidatesAreIgnored() {
        let road = Shapes.line(id: 3, points: [(x: 0, y: -200), (x: 0, y: 200)])
        XCTAssertEqual(Driver(candidates: [road, southApproachStop()]).changes(northboundPath()), [
            .stopApproachStarted(key(0), Points.mark(4)),
            .stopReached(passage(0, started: 4, reached: 11)),
        ])
    }
}

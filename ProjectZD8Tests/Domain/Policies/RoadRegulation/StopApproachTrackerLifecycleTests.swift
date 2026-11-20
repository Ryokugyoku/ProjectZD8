import XCTest
@testable import ProjectZD8

/// `StopApproachTracker` の打ち切り・再検出の待ち・記録の空白・複数の進入方向を検証します(設計書 §3.5、TB6)。
///
/// S は原点、E は南へ 15 m(s = 北への距離 y、l = |x|)。精度 5 の許容は 13 m、打ち切りは s < −50・l > 23・角度差 > 90。
/// 再検出の待ちは S から 60 m を超えて離れたら解除します。境界は ±0.5 m で確かめます。
@MainActor
final class StopApproachTrackerLifecycleTests: XCTestCase {
    private typealias Driver = StopApproachTrackerTestDriver
    private typealias Shapes = RoadRegulationMeterRegulationFactory
    private typealias Points = RoadRegulationMeterTrackPointFactory

    /// 責務: 規制 `id`・進入方向 `index` の鍵を返します。
    private func key(_ index: Int, id: Int64 = 10) -> StopApproachKey {
        StopApproachKey(regulationID: RoadRegulationID(rawValue: id), approachIndex: index)
    }

    /// 責務: S が原点・E が南へ 15 m の一時停止を返します。
    private func southApproachStop() -> RoadRegulation {
        Shapes.stop(id: 10, at: (x: 0, y: 0), approaches: [(x: 0, y: -15)])
    }

    /// 責務: 北向き(0 度)・精度 5 の経路を返します。
    private func north(_ points: [(x: Double, y: Double)]) -> [Driver.PathPoint] {
        points.map { (x: $0.x, y: $0.y, heading: 0, accuracy: 5) }
    }

    /// 責務: 開始と到達の連番から通過を返します。
    private func passage(_ key: StopApproachKey, started: Int64, reached: Int64) -> StopPassage {
        StopPassage(key: key, approachStarted: Points.mark(started), reached: Points.mark(reached), applicability: .applies, interruptedByGap: false)
    }

    /// 責務: 接近中に s = −50.5(打ち切りの境界 −50 の外)へ下がると打ち切り、−49.5 なら続けて到達することを確かめます。
    func testFallingBehindApproachRangeAbandons() {
        let stop = southApproachStop()
        XCTAssertEqual(Driver(candidates: [stop]).changes(north([(0, -38), (0, -50.5)])), [
            .stopApproachStarted(key(0), Points.mark(0)), .stopApproachAbandoned(key(0)),
        ])
        XCTAssertEqual(Driver(candidates: [stop]).changes(north([(0, -38), (0, -49.5), (0, -3)])), [
            .stopApproachStarted(key(0), Points.mark(0)), .stopReached(passage(key(0), started: 0, reached: 2)),
        ])
    }

    /// 責務: 接近中に横へ 23.5 m(許容 13 + 10 = 23 の外)外れると打ち切り、22.5 m なら続けて到達することを確かめます。
    func testDriftingSidewaysAbandons() {
        let stop = southApproachStop()
        XCTAssertEqual(Driver(candidates: [stop]).changes(north([(0, -38), (23.5, -20)])), [
            .stopApproachStarted(key(0), Points.mark(0)), .stopApproachAbandoned(key(0)),
        ])
        XCTAssertEqual(Driver(candidates: [stop]).changes(north([(0, -38), (22.5, -20), (0, -3)])), [
            .stopApproachStarted(key(0), Points.mark(0)), .stopReached(passage(key(0), started: 0, reached: 2)),
        ])
    }

    /// 責務: 到達の後、S から 59.5 m までしか離れずに戻って来ても、再び開始しないことを確かめます(再検出の待ち)。
    func testReturningWithinRearmDistanceIsNotDetectedAgain() {
        let path = north([(0, -38), (0, -3), (0, -59.5), (0, -38), (0, -20), (0, -3)])
        XCTAssertEqual(Driver(candidates: [southApproachStop()]).changes(path), [
            .stopApproachStarted(key(0), Points.mark(0)), .stopReached(passage(key(0), started: 0, reached: 1)),
        ])
    }

    /// 責務: 到達の後、S から 60.5 m 離れてから戻って来ると、再び開始と到達が出ることを確かめます。
    func testReturningAfterRearmDistanceIsDetectedAgain() {
        let path = north([(0, -38), (0, -3), (0, -60.5), (0, -38), (0, -3)])
        XCTAssertEqual(Driver(candidates: [southApproachStop()]).changes(path), [
            .stopApproachStarted(key(0), Points.mark(0)), .stopReached(passage(key(0), started: 0, reached: 1)),
            .stopApproachStarted(key(0), Points.mark(3)), .stopReached(passage(key(0), started: 3, reached: 4)),
        ])
    }

    /// 責務: 再検出の距離を 30 m に縮めると、30.5 m 離れた点で待ちが解け、同じ点で再び開始することを確かめます(埋め込みの数値でない)。
    ///
    /// 1歩の中では待ちの解除が先、新しい接近の開始が後です。標準(60 m)なら同じ経路で再び開始しません。
    func testRearmDistanceIsConfigurable() {
        let path = north([(0, -38), (0, -3), (0, -30.5), (0, -25)])
        var driver = Driver(candidates: [southApproachStop()])
        driver.thresholds.stopRearmDistanceMeters = 30
        XCTAssertEqual(driver.changes(path), [
            .stopApproachStarted(key(0), Points.mark(0)), .stopReached(passage(key(0), started: 0, reached: 1)),
            .stopApproachStarted(key(0), Points.mark(2)),
        ])
        XCTAssertEqual(Driver(candidates: [southApproachStop()]).changes(path).count, 2)
    }

    /// 責務: 進入方向の点が2つの地点で、東からの進入(添字1、方位 270 度)と南からの進入(添字0)を別々の鍵で扱うことを確かめます。
    ///
    /// 東の点 E1 = (15, 0) では u = 西、s = −x。x = 43 から西へ 5 m 刻みで進むと x = 38 で開始、x = 3 で到達します。
    func testEachApproachPointIsTrackedSeparately() {
        let stop = Shapes.stop(id: 10, at: (x: 0, y: 0), approaches: [(x: 0, y: -15), (x: 15, y: 0)])
        let westbound = Driver.values(from: 43, through: -7, by: -5).map { (x: $0, y: 0.0, heading: Double?(270), accuracy: 5.0) }
        XCTAssertEqual(Driver(candidates: [stop]).changes(westbound), [
            .stopApproachStarted(key(1), Points.mark(1)), .stopReached(passage(key(1), started: 1, reached: 8)),
        ])
        XCTAssertEqual(Driver(candidates: [stop]).changes(north([(0, -38), (0, -3)])), [
            .stopApproachStarted(key(0), Points.mark(0)), .stopReached(passage(key(0), started: 0, reached: 1)),
        ])
    }

    /// 責務: S から 1.5 m(2 m 未満)の進入方向は追わず、2.5 m なら追うことを確かめます。添字は元の並びのまま残ることも確かめます。
    func testApproachPointTooCloseToStopIsNotTracked() {
        let tooClose = Shapes.stop(id: 10, at: (x: 0, y: 0), approaches: [(x: 0, y: -1.5)])
        let farEnough = Shapes.stop(id: 10, at: (x: 0, y: 0), approaches: [(x: 0, y: -2.5)])
        let samePointFirst = Shapes.stop(id: 10, at: (x: 0, y: 0), approaches: [(x: 0, y: 0), (x: 0, y: -15)])
        let path = north([(0, -38), (0, -3)])
        XCTAssertEqual(Driver(candidates: [tooClose]).changes(path), [])
        XCTAssertEqual(Driver(candidates: [farEnough]).changes(path), [
            .stopApproachStarted(key(0), Points.mark(0)), .stopReached(passage(key(0), started: 0, reached: 1)),
        ])
        XCTAssertEqual(Driver(candidates: [samePointFirst]).changes(path), [
            .stopApproachStarted(key(1), Points.mark(0)), .stopReached(passage(key(1), started: 0, reached: 1)),
        ])
    }
}

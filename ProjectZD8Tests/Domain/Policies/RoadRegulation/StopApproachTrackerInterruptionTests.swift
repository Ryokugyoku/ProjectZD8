import XCTest
@testable import ProjectZD8

/// `StopApproachTracker` の、位置の空白(`interruptAll`)・候補からの消失・条件の判定の時点・同じ一時停止の複数の接近を検証します
/// (設計書 §3.5、TB6。設計書に書かれていなかった点は管理役の確定事項に従います)。
///
/// S は原点、E は南へ 15 m(s = 北への距離 y)。精度 5 の許容は 13 m。経路は北向き(0 度)です。
@MainActor
final class StopApproachTrackerInterruptionTests: XCTestCase {
    private typealias Driver = StopApproachTrackerTestDriver
    private typealias Shapes = RoadRegulationMeterRegulationFactory
    private typealias Points = RoadRegulationMeterTrackPointFactory

    /// 責務: 規制 `id`・進入方向 `index` の鍵を返します。
    private func key(_ index: Int, id: Int64 = 10) -> StopApproachKey {
        StopApproachKey(regulationID: RoadRegulationID(rawValue: id), approachIndex: index)
    }

    /// 責務: S が (x, 0)・E が (x, −15) の一時停止を返します。
    private func southApproachStop(id: Int64 = 10, x: Double = 0) -> RoadRegulation {
        Shapes.stop(id: id, at: (x: x, y: 0), approaches: [(x: x, y: -15)])
    }

    /// 責務: 北向き・精度 5 の経路を返します。
    private func north(_ points: [(x: Double, y: Double)], heading: Double? = 0) -> [Driver.PathPoint] {
        points.map { (x: $0.x, y: $0.y, heading: heading, accuracy: 5) }
    }

    /// 責務: 通過を返します(到達は印で渡す)。
    private func passage(
        _ key: StopApproachKey,
        started: Int64,
        reached: RoadRegulationTransitionMark,
        applicability: RegulationApplicability = .applies,
        gap: Bool = false
    ) -> StopPassage {
        StopPassage(key: key, approachStarted: Points.mark(started), reached: reached, applicability: applicability, interruptedByGap: gap)
    }

    /// 責務: 接近中に空白が来たら、最後に使えた点で到達した `interruptedByGap = true` の通過を出すことを確かめます。
    func testGapTurnsActiveApproachIntoInterruptedPassage() {
        let started = Driver(candidates: [southApproachStop()]).run(north([(0, -38), (0, -33)]))
        let lastUsable = Points.mark(1)
        let interrupted = StopApproachTracker().interruptAll(started.state, lastUsable: lastUsable)
        XCTAssertEqual(interrupted.1, [.stopReached(passage(key(0), started: 0, reached: lastUsable, gap: true))])
    }

    /// 責務: 空白で到達扱いにした一時停止は再検出の待ちに入り、空白の後に続けて近づいても開始も到達も出ないことを確かめます。
    func testGapPutsStopIntoRearmWait() {
        let driver = Driver(candidates: [southApproachStop()])
        let started = driver.run(north([(0, -38)]))
        let interrupted = StopApproachTracker().interruptAll(started.state, lastUsable: Points.mark(0))
        let after = driver.run(north([(0, -30), (0, -3)]), from: interrupted.0, firstSequence: 20)
        XCTAssertEqual(after.changesPerPoint.flatMap { $0 }, [])
    }

    /// 責務: 接近が無い状態で空白が来ても何も出ないことを確かめます。
    func testGapWithoutActiveApproachEmitsNothing() {
        XCTAssertEqual(StopApproachTracker().interruptAll(.initial, lastUsable: Points.mark(3)).1, [])
    }

    /// 責務: 別々の一時停止2件へ同時に接近している時の空白は、それぞれに空白の通過を id の昇順で出すことを確かめます。
    /// 開始時の条件が不明なら、空白の通過にも不明が入ることも確かめます。
    func testGapInterruptsEveryStopInIDOrder() {
        var driver = Driver(candidates: [southApproachStop(id: 12, x: 5), southApproachStop(id: 11, x: 0)])
        driver.applicability = .unknown
        let started = driver.run(north([(2, -38)]))
        let lastUsable = Points.mark(0)
        XCTAssertEqual(StopApproachTracker().interruptAll(started.state, lastUsable: lastUsable).1, [
            .stopReached(passage(key(0, id: 11), started: 0, reached: lastUsable, applicability: .unknown, gap: true)),
            .stopReached(passage(key(0, id: 12), started: 0, reached: lastUsable, applicability: .unknown, gap: true)),
        ])
    }

    /// 責務: 同じ一時停止の2つの進入方向へ同時に接近している時の空白は、1件目を空白の通過に、2件目を打ち切りにすることを確かめます。
    func testGapCountsOneStopOnlyOnce() {
        let stop = Shapes.stop(id: 10, at: (x: 0, y: 0), approaches: [(x: 0, y: -15), (x: 0, y: -30)])
        let started = Driver(candidates: [stop]).run(north([(0, -38)]))
        let lastUsable = Points.mark(0)
        XCTAssertEqual(StopApproachTracker().interruptAll(started.state, lastUsable: lastUsable).1, [
            .stopReached(passage(key(0), started: 0, reached: lastUsable, gap: true)),
            .stopApproachAbandoned(key(1)),
        ])
    }

    /// 責務: 同じ線上に進入方向が2つある一時停止を北向きに通ると、開始2件・到達1件(添字0)・打ち切り1件(添字1)になることを確かめます。
    func testTwoApproachesOnSameLineReachOnce() {
        let stop = Shapes.stop(id: 10, at: (x: 0, y: 0), approaches: [(x: 0, y: -15), (x: 0, y: -30)])
        XCTAssertEqual(Driver(candidates: [stop]).changes(north([(0, -38), (0, -3)])), [
            .stopApproachStarted(key(0), Points.mark(0)), .stopApproachStarted(key(1), Points.mark(0)),
            .stopReached(passage(key(0), started: 0, reached: Points.mark(1))), .stopApproachAbandoned(key(1)),
        ])
    }

    /// 責務: 接近中の一時停止が候補から消えたら打ち切ることを確かめます。
    func testStopMissingFromCandidatesAbandonsApproach() {
        let started = Driver(candidates: [southApproachStop()]).run(north([(0, -38)]))
        let after = Driver(candidates: []).run(north([(0, -20)]), from: started.state, firstSequence: 1)
        XCTAssertEqual(after.changesPerPoint, [[.stopApproachAbandoned(key(0))]])
    }

    /// 責務: 条件は開始時に1度だけ判定し、その後に判定が変わっても(不明 → 当てはまらない)開始時の値で通過を出すことを確かめます。
    func testApplicabilityIsTakenAtStart() {
        var unknownDriver = Driver(candidates: [southApproachStop()])
        unknownDriver.applicability = .unknown
        let started = unknownDriver.run(north([(0, -38)]))
        var laterDriver = Driver(candidates: [southApproachStop()])
        laterDriver.applicability = .doesNotApply
        let after = laterDriver.run(north([(0, -3)]), from: started.state, firstSequence: 1)
        XCTAssertEqual(after.changesPerPoint, [[.stopReached(passage(key(0), started: 0, reached: Points.mark(1), applicability: .unknown))]])
    }

    /// 責務: 接近中に向きが分からなくなっても向きでは打ち切らず、そのまま到達することを確かめます。
    func testUnknownHeadingDuringApproachDoesNotAbandon() {
        let path = north([(0, -38)]) + north([(0, -20), (0, -3)], heading: nil)
        XCTAssertEqual(Driver(candidates: [southApproachStop()]).changes(path), [
            .stopApproachStarted(key(0), Points.mark(0)), .stopReached(passage(key(0), started: 0, reached: Points.mark(2))),
        ])
    }
}

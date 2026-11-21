import XCTest
@testable import ProjectZD8

/// `OneWayJudge` が、一方通行の区間を設計書 §3.6(一方通行)どおりに判定することを検証します。
///
/// 軌跡は緯度0・経度0から北へ並べます(緯度0では2点間の距離は Δ緯度 × 111,195.08 m)。
/// 距離は浮動小数点の誤差を含むため、境界ちょうどは避けて少し上(+0.01 m)と少し下(−0.01 m)で確かめ、距離は ±0.01 m で比べます。
@MainActor
final class OneWayJudgeTests: XCTestCase {
    private typealias Fixtures = RoadRegulationJudgementFixtures
    private typealias Points = [(north: Double, east: Double, accuracy: Double)]
    private let standard = RoadRegulationMatchingThresholds.standard
    /// 必要な距離が既定の 50 m になる長い区間の長さ(m)。
    private let longSectionMeters = 500.0
    /// 距離を比べる時の誤差(m)。
    private let distanceAccuracy = 0.01

    /// 責務: 軌跡全体を区間として、状態 `status` の一方通行を判定します。
    private func verdict(
        _ points: Points,
        status: OneWayChannelStatus = .on(Fixtures.regulationID, .reverse),
        regulationLengthMeters: Double? = nil,
        thresholds: RoadRegulationMatchingThresholds = .standard
    ) -> OneWayVerdict {
        let track = Fixtures.track(points)
        return OneWayJudge(thresholds: thresholds)
            .judge(Fixtures.oneWayTraversal(status, over: track), track: track[...], regulationLengthMeters: regulationLengthMeters ?? longSectionMeters)
            .verdict
    }

    /// 責務: 判定が「逆走の可能性」で、距離が期待値と誤差の範囲で一致することを確かめます。
    private func assertWrongWay(_ verdict: OneWayVerdict, meters expected: Double, file: StaticString = #filePath, line: UInt = #line) {
        guard case let .possibleWrongWay(distance) = verdict else {
            return XCTFail("逆走の可能性になるはずです: \(verdict)", file: file, line: line)
        }
        XCTAssertEqual(distance, expected, accuracy: distanceAccuracy, file: file, line: line)
    }

    /// 責務: 北へ `meters` m をまっすぐ進む2点の軌跡を作ります。
    private func straight(_ meters: Double, accuracy: Double = 5) -> Points {
        [(0, 0, accuracy), (meters, 0, accuracy)]
    }

    /// 責務: 北へ 10 m 間隔で `count` 区間進む軌跡を作ります。
    private func evenlySpaced(_ count: Int, accuracy: Double = 5) -> Points {
        (0...count).map { (north: Double($0) * 10, east: 0, accuracy: accuracy) }
    }

    /// 責務: 通行できる向きに進んだ区間は、軌跡によらず向きどおりになり、判定結果が区間を持つことを確かめます。
    func testPermittedDirectionIsFollowed() {
        XCTAssertEqual(verdict(evenlySpaced(10), status: .on(Fixtures.regulationID, .permitted)), .followedDirection)
        XCTAssertEqual(verdict([], status: .on(Fixtures.regulationID, .permitted)), .followedDirection)
        let track = Fixtures.track(straight(100))
        let traversal = Fixtures.oneWayTraversal(.on(Fixtures.regulationID, .permitted), over: track)
        let judgement = OneWayJudge(thresholds: standard).judge(traversal, track: track[...], regulationLengthMeters: longSectionMeters)
        XCTAssertEqual(judgement.traversal, traversal)
    }

    /// 責務: 判定できない区間は、その理由のまま判定できないになることを確かめます。
    func testUndeterminableStatusKeepsItsReason() {
        let reasons: [RoadRegulationUndeterminedReason] = [.headingUnknown, .ambiguousCandidates, .coarseGeometry, .conditionUnknown]
        for reason in reasons {
            XCTAssertEqual(verdict(evenlySpaced(10), status: .undeterminable(reason, Fixtures.regulationID)), .undeterminable(reason), "\(reason)")
        }
    }

    /// 責務: 一方通行に乗っていない状態(`none`)や別の経路の状態が渡されたら、規制データの範囲外として判定できないことを確かめます。
    func testNonOneWayStatusIsOutsideRegulationData() {
        XCTAssertEqual(verdict(evenlySpaced(10), status: .none), .undeterminable(.outsideRegulationData))
        let track = Fixtures.track(evenlySpaced(10))
        let speedTraversal = Fixtures.traversal(.speedLimit(.regulated(Fixtures.regulationID, limitKph: 40)), from: 0, to: 10, sequences: 0...10)
        let judgement = OneWayJudge(thresholds: standard).judge(speedTraversal, track: track[...], regulationLengthMeters: longSectionMeters)
        XCTAssertEqual(judgement.verdict, .undeterminable(.outsideRegulationData))
    }

    /// 責務: 逆向きに約 100 m(10 m × 10 区間)進むと、逆走の可能性(約 100 m)になることを確かめます。
    func testReverseHundredMetersIsPossibleWrongWay() {
        assertWrongWay(verdict(evenlySpaced(10)), meters: 100)
    }

    /// 責務: 逆向きに 30 m しか進まなければ、長い区間(必要 50 m)では距離不足になることを確かめます。
    func testReverseThirtyMetersIsInsufficientDistance() {
        XCTAssertEqual(standard.wrongWayRequiredDistance(regulationLengthMeters: longSectionMeters), 50)
        XCTAssertEqual(verdict(evenlySpaced(3)), .undeterminable(.insufficientDistance))
    }

    /// 責務: 長い区間で、必要な距離 50 m の少し上(50.01)は逆走の可能性、少し下(49.99)は距離不足になることを確かめます。
    func testRequiredDistanceBoundaryOnLongSection() {
        assertWrongWay(verdict(straight(50.01)), meters: 50.01)
        XCTAssertEqual(verdict(straight(49.99)), .undeterminable(.insufficientDistance))
    }

    /// 責務: 区間長 30 m では必要な距離が 0.8 × 30 = 24 m になり、24.01 m は逆走の可能性、23.99 m は距離不足になることを確かめます。
    func testShortSectionScalesRequiredDistance() {
        XCTAssertEqual(standard.wrongWayRequiredDistance(regulationLengthMeters: 30), 24, accuracy: 1e-9)
        assertWrongWay(verdict(straight(24.01), regulationLengthMeters: 30), meters: 24.01)
        XCTAssertEqual(verdict(straight(23.99), regulationLengthMeters: 30), .undeterminable(.insufficientDistance))
    }

    /// 責務: 区間長 10 m では必要な距離が下限の 20 m になり、20.01 m は逆走の可能性、19.99 m は距離不足になることを確かめます。
    func testVeryShortSectionUsesMinimumRequiredDistance() {
        XCTAssertEqual(standard.wrongWayRequiredDistance(regulationLengthMeters: 10), 20)
        assertWrongWay(verdict(straight(20.01), regulationLengthMeters: 10), meters: 20.01)
        XCTAssertEqual(verdict(straight(19.99), regulationLengthMeters: 10), .undeterminable(.insufficientDistance))
    }

    /// 責務: 精度が 20 m を超える点が過半数なら、距離が十分でも「精度が低い」になることを確かめます(5点中3点)。
    func testMajorityOfLowAccuracyPointsIsLowAccuracy() {
        let points: Points = [(0, 0, 5), (50, 0, 25), (100, 0, 25), (150, 0, 25), (200, 0, 5)]
        XCTAssertEqual(verdict(points), .undeterminable(.lowAccuracy))
    }

    /// 責務: 精度の悪い点がちょうど半分なら精度不足にせず、精度の良い点だけを順に結んだ距離で判定することを確かめます。
    ///
    /// 精度の悪い2点は東へ 500 m ずらしてあり、距離に含めると 1,000 m を超えます。
    func testHalfLowAccuracyPointsAreSkippedInDistance() {
        let points: Points = [(0, 0, 5), (30, 500, 25), (45, 500, 25), (60, 0, 5)]
        assertWrongWay(verdict(points), meters: 60)
    }

    /// 責務: 精度 20 m ちょうどの点は距離に数え、20.01 m の点は精度の悪い点として数えることを確かめます。
    func testAccuracyBoundaryOfCountedPoints() {
        assertWrongWay(verdict(straight(60, accuracy: standard.wrongWayMaximumAccuracyMeters)), meters: 60)
        XCTAssertEqual(verdict(evenlySpaced(4, accuracy: 20.01)), .undeterminable(.lowAccuracy))
    }

    /// 責務: 区間の連番(開始〜終了)の外にある点を、距離にも精度の数にも使わないことを確かめます。
    func testPointsOutsideTraversalSequencesAreIgnored() {
        let track = Fixtures.track([(0, 0, 25), (10, 0, 25), (20, 0, 5), (60, 0, 5), (500, 0, 5), (900, 0, 25), (950, 0, 25)])
        let traversal = Fixtures.traversal(.oneWay(.on(Fixtures.regulationID, .reverse)), from: 2, to: 3, sequences: 2...3)
        let judgement = OneWayJudge(thresholds: standard).judge(traversal, track: track[...], regulationLengthMeters: longSectionMeters)
        XCTAssertEqual(judgement.verdict, .undeterminable(.insufficientDistance))
        let wider = Fixtures.traversal(.oneWay(.on(Fixtures.regulationID, .reverse)), from: 2, to: 4, sequences: 2...4)
        assertWrongWay(OneWayJudge(thresholds: standard).judge(wider, track: track[...], regulationLengthMeters: longSectionMeters).verdict, meters: 480)
    }

    /// 責務: 逆向きの区間に点が1つも無ければ、距離 0 で距離不足になることを確かめます。
    func testReverseWithoutPointsIsInsufficientDistance() {
        XCTAssertEqual(verdict([]), .undeterminable(.insufficientDistance))
    }

    /// 責務: 既定の必要な距離を 120 m にすると、標準では逆走の可能性の 100 m が距離不足になることを確かめます。
    func testCustomRequiredDistanceChangesVerdict() {
        var custom = standard
        custom.wrongWayMinimumDistanceMeters = 120
        XCTAssertEqual(verdict(evenlySpaced(10), thresholds: custom), .undeterminable(.insufficientDistance))
    }

    /// 責務: 数える点の精度の上限を 30 m にすると、標準では精度不足の 25 m の点が距離に数えられることを確かめます。
    func testCustomAccuracyLimitChangesVerdict() {
        var custom = standard
        custom.wrongWayMaximumAccuracyMeters = 30
        XCTAssertEqual(verdict(straight(60, accuracy: 25)), .undeterminable(.lowAccuracy))
        assertWrongWay(verdict(straight(60, accuracy: 25), thresholds: custom), meters: 60)
    }
}

import XCTest
@testable import ProjectZD8

/// `DrivingRouteSegmenter` の、点と点の間にある事象による区切りを設計書 §2.1・§9 T3-1・§11 R6 で検証します。
/// 事象の時刻 t と点の時刻 prev・next の関係は `prev < t ≤ next` で切ります。
@MainActor
final class DrivingRouteSegmenterEventTests: XCTestCase {
    private typealias Fixtures = DrivingRouteTrackFixtures
    private let segmenter = DrivingRouteSegmenter()

    /// 記録中以外の事象の7種です。
    private var interruptingKinds: [ConnectionSessionLocationEventKind] {
        ConnectionSessionLocationEventKind.allCases.filter {
            $0 != .recording && $0 != .recordingWithReducedAccuracy
        }
    }

    /// 責務: 時刻 0 と 10 の2点の間に、指定の事象を置いた時の区間の連番を返します。
    private func shape(_ events: [ConnectionSessionLocationEvent]) -> [[Int64]] {
        let samples = [Fixtures.sample(0, at: 0), Fixtures.sample(1, at: 10)]
        return Fixtures.sequences(of: segmenter.route(from: Fixtures.track(samples, events: events)))
    }

    /// 責務: 記録中以外の7種の事象が、2点の間(t = 5)にあれば、種類を問わず切ることを確かめます。
    func testEachInterruptingKindBetweenPointsCuts() {
        XCTAssertEqual(interruptingKinds.count, 7)
        for kind in interruptingKinds {
            XCTAssertEqual(shape([Fixtures.event(0, at: 5, kind)]), [[0], [1]], "\(kind)")
        }
    }

    /// 責務: 事象の時刻が前の点と同じ(t = prev)なら、切らないことを確かめます。
    func testEventAtPreviousPointTimeDoesNotCut() {
        for kind in interruptingKinds {
            XCTAssertEqual(shape([Fixtures.event(0, at: 0, kind)]), [[0, 1]], "\(kind)")
        }
    }

    /// 責務: 事象の時刻が次の点と同じ(t = next)なら、切ることを確かめます。
    func testEventAtNextPointTimeCuts() {
        for kind in interruptingKinds {
            XCTAssertEqual(shape([Fixtures.event(0, at: 10, kind)]), [[0], [1]], "\(kind)")
        }
    }

    /// 責務: 事象が前の点の少し前、または次の点の少し後なら、切らないことを確かめます。
    func testEventJustOutsideTheIntervalDoesNotCut() {
        XCTAssertEqual(shape([Fixtures.event(0, at: -0.001, .authorizationDenied)]), [[0, 1]])
        XCTAssertEqual(shape([Fixtures.event(0, at: 10.001, .authorizationDenied)]), [[0, 1]])
    }

    /// 責務: 前の点の少し後(t = prev + 0.001)の事象は、切ることを確かめます。
    func testEventJustAfterPreviousPointCuts() {
        XCTAssertEqual(shape([Fixtures.event(0, at: 0.001, .locationUnavailable)]), [[0], [1]])
    }

    /// 責務: 記録中の事象が間にあっても、同じ精度の段階なら切らないことを確かめます。
    func testRecordingEventBetweenPointsDoesNotCut() {
        let events = [Fixtures.event(0, at: -10, .recording), Fixtures.event(1, at: 5, .recording)]
        XCTAssertEqual(shape(events), [[0, 1]])
    }

    /// 責務: 事象が間にある場所だけで切り、ほかの隣り合う点はつなぐことを確かめます。
    func testEventCutsOnlyBetweenTheSurroundingPoints() {
        let samples = [Fixtures.sample(0, at: 0), Fixtures.sample(1, at: 5), Fixtures.sample(2, at: 10)]
        let events = [Fixtures.event(0, at: 7, .backgroundWithoutAlwaysAuthorization)]
        let route = segmenter.route(from: Fixtures.track(samples, events: events))
        XCTAssertEqual(Fixtures.sequences(of: route), [[0, 1], [2]])
    }

    /// 責務: 事象が全点の前後だけにある時は、何も切らないことを確かめます。
    func testEventsBeforeFirstAndAfterLastPointDoNotCut() {
        let events = [Fixtures.event(0, at: -50, .authorizationNotDetermined), Fixtures.event(1, at: 50, .disabledBySetting)]
        XCTAssertEqual(shape(events), [[0, 1]])
    }

    /// 責務: 事象の番号順と時刻順が逆でも(番号0が遅い時刻)、間にある事象で切ることを確かめます。
    func testEventsWithReversedTimesStillCut() {
        let late = Fixtures.event(0, at: 100, .locationUnavailable)
        let inside = Fixtures.event(1, at: 5, .locationUnavailable)
        XCTAssertEqual(shape([late, inside]), [[0], [1]])
        let inside2 = Fixtures.event(0, at: 5, .locationUnavailable)
        let early = Fixtures.event(1, at: -100, .locationUnavailable)
        XCTAssertEqual(shape([inside2, early]), [[0], [1]])
    }

    /// 責務: 除いた点を挟んでも、除いた点の時刻にある事象は残った前後の点の間なので切ることを確かめます。
    func testEventDuringExcludedPointStillCutsBetweenKeptNeighbors() {
        let samples = [
            Fixtures.sample(0, at: 0),
            Fixtures.sample(1, at: 5, accuracy: 60),
            Fixtures.sample(2, at: 10)
        ]
        let events = [Fixtures.event(0, at: 5, .locationUnavailable)]
        let route = segmenter.route(from: Fixtures.track(samples, events: events))
        XCTAssertEqual(Fixtures.sequences(of: route), [[0], [2]])
    }

    /// 責務: 事象の種類が違う複数の事象が同じ間にあっても、切れ目は1つであることを確かめます。
    func testMultipleEventsBetweenPointsMakeSingleCut() {
        let events = [Fixtures.event(0, at: 3, .authorizationDenied), Fixtures.event(1, at: 6, .locationUnavailable)]
        XCTAssertEqual(shape(events), [[0], [1]])
    }
}

import Foundation
import XCTest
@testable import ProjectZD8

/// 解析の走行ルートのモデルで、グラフ上の時刻の選択が地図の印(cursor)を同期で動かすことを検証します(設計書 §2.3、§3.4)。
@MainActor
final class RouteAnalysisModelCursorTests: XCTestCase {
    private typealias Values = RouteAnalysisModelTestValues

    /// モデルと部品の組です。
    private var harness = RouteAnalysisModelHarness()

    /// 責務: 止めた読み込みを必ず再開し、終わらないテストを残しません。
    override func tearDown() async throws {
        harness.port.gate.releaseAll()
        try await super.tearDown()
    }

    /// 責務: 位置のある時刻を選ぶと、すぐに(待たずに)その時刻と位置の印が入ることを確かめます。
    func testSelectingTimeMovesCursorSynchronously() async {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)

        harness.model.send(.timeSelected(DrivingRouteTestValues.date(3)))

        XCTAssertEqual(harness.state.cursor?.date, DrivingRouteTestValues.date(3))
        XCTAssertEqual(harness.state.cursor?.coordinate, Values.point(3).coordinate)
    }

    /// 責務: 最も近い位置まで 5 s を超える時刻を選ぶと、印(座標)が消えることを確かめます。
    func testSelectingTimeBeyondToleranceHidesMarker() async {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)
        harness.model.send(.timeSelected(DrivingRouteTestValues.date(3)))
        XCTAssertNotNil(harness.state.cursor?.coordinate)

        harness.model.send(.timeSelected(DrivingRouteTestValues.date(15)))

        XCTAssertNil(harness.state.cursor?.coordinate)
    }

    /// 責務: 選択を外す(`nil`)と、読み出しごと消えることを確かめます。
    func testClearingSelectionRemovesCursor() async {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)
        harness.model.send(.timeSelected(DrivingRouteTestValues.date(3)))

        harness.model.send(.timeSelected(nil))

        XCTAssertNil(harness.state.cursor)
    }

    /// 責務: 色分けの指標がある時は、選んだ時刻の値の文字が読み出しに入ることを確かめます。
    func testCursorShowsMetricValueWhenColored() async {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)
        harness.model.send(.timelineLoaded(session.id, Values.speedSamples()))
        await harness.waitUntil("speed coloring") { self.harness.state.selectedColorSource == .metric(.vehicleSpeed) }

        harness.model.send(.timeSelected(DrivingRouteTestValues.date(7)))

        XCTAssertNotNil(harness.state.cursor?.metricValueText)
        XCTAssertEqual(harness.state.cursor?.coordinate, Values.point(7).coordinate)
    }

    /// 責務: 時刻を選んだ後に色分けを作り直すと、読み出しを求め直して値の文字が入ることを確かめます。
    func testCursorIsRecomputedAfterRebuild() async {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)
        harness.model.send(.timeSelected(DrivingRouteTestValues.date(7)))
        XCTAssertNil(harness.state.cursor?.metricValueText)

        harness.model.send(.timelineLoaded(session.id, Values.speedSamples()))

        await harness.waitUntil("value text") { self.harness.state.cursor?.metricValueText != nil }
        XCTAssertEqual(harness.state.cursor?.date, DrivingRouteTestValues.date(7))
    }

    /// 責務: 地図の座標を選ぶと、200 m 以内の最も近い点の時刻と位置の読み出しになることを確かめます。
    func testMapCoordinateSelectsNearestPointTime() async {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)

        harness.model.send(.mapCoordinateSelected(Values.point(4).coordinate))

        XCTAssertEqual(harness.state.cursor?.date, DrivingRouteTestValues.date(4))
        XCTAssertEqual(harness.state.cursor?.coordinate, Values.point(4).coordinate)
    }

    /// 責務: 200 m 以内に点の無い座標を選ぶと、読み出しが消えることを確かめます。
    func testFarMapCoordinateClearsCursor() async throws {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)
        harness.model.send(.timeSelected(DrivingRouteTestValues.date(3)))
        let far = try XCTUnwrap(GeoCoordinate(latitude: DrivingRouteTestValues.baseLatitude + 0.1, longitude: DrivingRouteTestValues.baseLongitude))

        harness.model.send(.mapCoordinateSelected(far))

        XCTAssertNil(harness.state.cursor)
    }
}

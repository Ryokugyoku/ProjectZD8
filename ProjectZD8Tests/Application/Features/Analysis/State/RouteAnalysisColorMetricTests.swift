import XCTest
@testable import ProjectZD8

/// `RouteAnalysisColorMetric` の PID・文言キー・単位・区分の境界を設計書 §2.4 で検証します。
@MainActor
final class RouteAnalysisColorMetricTests: XCTestCase {
    /// 責務: 4つの指標がすべて列挙されることを確かめます。
    func testAllFourMetricsExist() {
        XCTAssertEqual(Set(RouteAnalysisColorMetric.allCases), [.vehicleSpeed, .engineSpeed, .engineLoad, .coolantTemperature])
    }

    /// 責務: 各指標の PID が service 0x01 の 0x0D / 0x0C / 0x04 / 0x05 であることを確かめます。
    func testPIDs() {
        XCTAssertEqual(RouteAnalysisColorMetric.vehicleSpeed.pid, OBDPIDRequest(service: 0x01, pid: 0x0D))
        XCTAssertEqual(RouteAnalysisColorMetric.engineSpeed.pid, OBDPIDRequest(service: 0x01, pid: 0x0C))
        XCTAssertEqual(RouteAnalysisColorMetric.engineLoad.pid, OBDPIDRequest(service: 0x01, pid: 0x04))
        XCTAssertEqual(RouteAnalysisColorMetric.coolantTemperature.pid, OBDPIDRequest(service: 0x01, pid: 0x05))
    }

    /// 責務: 各指標の文言キーが設計書のとおりで、互いに異なることを確かめます。
    func testTitleKeys() {
        XCTAssertEqual(RouteAnalysisColorMetric.vehicleSpeed.titleKey, "analysis.route.metric.vehicle_speed")
        XCTAssertEqual(RouteAnalysisColorMetric.engineSpeed.titleKey, "analysis.route.metric.engine_speed")
        XCTAssertEqual(RouteAnalysisColorMetric.engineLoad.titleKey, "analysis.route.metric.engine_load")
        XCTAssertEqual(RouteAnalysisColorMetric.coolantTemperature.titleKey, "analysis.route.metric.coolant_temperature")
        XCTAssertEqual(Set(RouteAnalysisColorMetric.allCases.map(\.titleKey)).count, 4)
    }

    /// 責務: 各指標の単位が km/h・rpm・%・°C であることを確かめます。
    func testFallbackUnits() {
        XCTAssertEqual(RouteAnalysisColorMetric.vehicleSpeed.fallbackUnit, "km/h")
        XCTAssertEqual(RouteAnalysisColorMetric.engineSpeed.fallbackUnit, "rpm")
        XCTAssertEqual(RouteAnalysisColorMetric.engineLoad.fallbackUnit, "%")
        XCTAssertEqual(RouteAnalysisColorMetric.coolantTemperature.fallbackUnit, "°C")
    }

    /// 責務: 各指標の境界が設計書 §2.4 の値であることを確かめます。
    func testBoundaries() {
        XCTAssertEqual(RouteAnalysisColorMetric.vehicleSpeed.bands.boundaries, [20, 40, 60, 80])
        XCTAssertEqual(RouteAnalysisColorMetric.engineSpeed.bands.boundaries, [1_500, 2_500, 3_500, 4_500])
        XCTAssertEqual(RouteAnalysisColorMetric.engineLoad.bands.boundaries, [20, 40, 60, 80])
        XCTAssertEqual(RouteAnalysisColorMetric.coolantTemperature.bands.boundaries, [60, 80, 95, 105])
    }

    /// 責務: どの指標も5区分で、境界が昇順であることを確かめます。
    func testEveryMetricHasFiveAscendingSteps() {
        for metric in RouteAnalysisColorMetric.allCases {
            XCTAssertEqual(metric.bands.stepCount, 5, "\(metric)")
            XCTAssertEqual(metric.bands.boundaries, metric.bands.boundaries.sorted(), "\(metric)")
        }
    }

    /// 責務: 水温の境界ちょうど(60 / 80 / 95 / 105)が上の区分になることを確かめます。
    func testCoolantBoundariesBelongToUpperStep() {
        let bands = RouteAnalysisColorMetric.coolantTemperature.bands
        XCTAssertEqual(bands.step(for: 59.9), 0)
        XCTAssertEqual(bands.step(for: 60), 1)
        XCTAssertEqual(bands.step(for: 94.9), 2)
        XCTAssertEqual(bands.step(for: 95), 3)
        XCTAssertEqual(bands.step(for: 105), 4)
    }

    /// 責務: エンジン回転の境界ちょうど(1,500 / 4,500)が上の区分になることを確かめます。
    func testEngineSpeedBoundariesBelongToUpperStep() {
        let bands = RouteAnalysisColorMetric.engineSpeed.bands
        XCTAssertEqual(bands.step(for: 1_499), 0)
        XCTAssertEqual(bands.step(for: 1_500), 1)
        XCTAssertEqual(bands.step(for: 4_500), 4)
    }
}

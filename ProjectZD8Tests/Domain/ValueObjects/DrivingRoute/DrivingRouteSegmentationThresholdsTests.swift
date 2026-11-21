import XCTest
@testable import ProjectZD8

/// `DrivingRouteSegmentationThresholds.standard` が設計書 §2.1 の値であることを検証します。
@MainActor
final class DrivingRouteSegmentationThresholdsTests: XCTestCase {
    /// 責務: 正確な位置の時間差の上限が 10 s であることを確かめます。
    func testPreciseGap() {
        XCTAssertEqual(DrivingRouteSegmentationThresholds.standard.preciseMaximumGapSeconds, 10)
    }

    /// 責務: 概略の位置の時間差の上限が 1,200 s であることを確かめます。
    func testApproximateGap() {
        XCTAssertEqual(DrivingRouteSegmentationThresholds.standard.approximateMaximumGapSeconds, 1_200)
    }

    /// 責務: 正確な位置の水平精度の上限が 50 m であることを確かめます。
    func testPreciseAccuracy() {
        XCTAssertEqual(DrivingRouteSegmentationThresholds.standard.preciseMaximumHorizontalAccuracyMeters, 50)
    }

    /// 責務: 概略の位置の水平精度の上限が 5,000 m であることを確かめます。
    func testApproximateAccuracy() {
        XCTAssertEqual(DrivingRouteSegmentationThresholds.standard.approximateMaximumHorizontalAccuracyMeters, 5_000)
    }

    /// 責務: 推定の速さの上限が 90 m/s であることを確かめます。
    func testMaximumImpliedSpeed() {
        XCTAssertEqual(DrivingRouteSegmentationThresholds.standard.maximumImpliedSpeedMetersPerSecond, 90)
    }
}

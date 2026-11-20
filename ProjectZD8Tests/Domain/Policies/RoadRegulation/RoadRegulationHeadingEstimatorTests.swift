import XCTest
@testable import ProjectZD8

/// `RoadRegulationHeadingEstimator` が、設計書 §3.4 の順(GPS の進行方向 → 基準点からの方位 → 前の向き)で向きを決めることを検証します。
///
/// しきい値は `standard`(進行方向を信じる GPS の速さ 1.5 m/s 以上、方位を求める移動 5 m 以上)です。境界はちょうどの値を避け、
/// 少し内側と少し外側で確かめます。期待する方位は、メートル単位の移動 (Δx 東, Δy 北) から atan2(Δx, Δy) で求めた値です。
@MainActor
final class RoadRegulationHeadingEstimatorTests: XCTestCase {
    private typealias Shapes = RoadRegulationMeterRegulationFactory
    private typealias Points = RoadRegulationMeterTrackPointFactory

    /// 責務: 向き 10 度・基準点が原点の状態を返します。
    private func stateHeadingTenAtOrigin() -> RoadRegulationHeadingState {
        RoadRegulationHeadingState(headingDegrees: 10, anchor: Shapes.coordinate((x: 0, y: 0)))
    }

    /// 責務: 推定した向きが期待の方位と 0.01 度以内(360 度の折り返しを考える)で一致することを確かめます。
    private func assertHeading(_ actual: Double?, _ expected: Double, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else {
            XCTFail("向きが nil です(期待 \(expected))", file: file, line: line)
            return
        }
        let remainder = abs(actual - expected).truncatingRemainder(dividingBy: 360)
        XCTAssertLessThan(min(remainder, 360 - remainder), 0.01, "向き \(actual)、期待 \(expected)", file: file, line: line)
    }

    /// 責務: 最初の1点で進行方向も基準点も無ければ、向きは決まらない(nil)ことを確かめます。
    func testFirstPointWithoutCourseHasNoHeading() {
        let next = RoadRegulationHeadingEstimator().next(.initial, point: Points.point(x: 0, y: 0, course: nil, speed: 3))
        XCTAssertNil(next.headingDegrees)
    }

    /// 責務: 最初の1点でも、進行方向と速さ 2 m/s があれば進行方向を使うことを確かめます。
    func testCourseWithSufficientSpeedIsUsedOnFirstPoint() {
        let next = RoadRegulationHeadingEstimator().next(.initial, point: Points.point(x: 0, y: 0, course: 123, speed: 2))
        assertHeading(next.headingDegrees, 123)
    }

    /// 責務: 速さの境界(1.5 m/s)の少し上の 1.6 では進行方向を使い、少し下の 1.4 では使わず前の向きを保つことを確かめます。
    func testCourseSpeedBoundary() {
        let estimator = RoadRegulationHeadingEstimator()
        let above = estimator.next(stateHeadingTenAtOrigin(), point: Points.point(x: 0, y: 1, course: 77, speed: 1.6))
        let below = estimator.next(stateHeadingTenAtOrigin(), point: Points.point(x: 0, y: 1, course: 77, speed: 1.4))
        assertHeading(above.headingDegrees, 77)
        assertHeading(below.headingDegrees, 10)
    }

    /// 責務: 進行方向があっても GPS の速さが無ければ進行方向を使わないことを確かめます。
    func testCourseWithoutSpeedIsNotUsed() {
        let next = RoadRegulationHeadingEstimator().next(stateHeadingTenAtOrigin(), point: Points.point(x: 0, y: 1, course: 77, speed: nil))
        assertHeading(next.headingDegrees, 10)
    }

    /// 責務: 進行方向が無く基準点から東へ 6 m 動いたら、基準点からの方位 90 度を使うことを確かめます。
    func testDisplacementWithoutCourseGivesBearing() {
        let next = RoadRegulationHeadingEstimator().next(stateHeadingTenAtOrigin(), point: Points.point(x: 6, y: 0, course: nil, speed: 3))
        assertHeading(next.headingDegrees, 90)
    }

    /// 責務: 速さ 1 m/s(進行方向を信じない)で南西へ 6 m 動いたら、進行方向 10 度でなく方位 225 度を使うことを確かめます。
    func testLowSpeedUsesBearingInsteadOfCourse() {
        let distance = 6 / 2.0.squareRoot()
        let point = Points.point(x: -distance, y: -distance, course: 10, speed: 1)
        let next = RoadRegulationHeadingEstimator().next(stateHeadingTenAtOrigin(), point: point)
        assertHeading(next.headingDegrees, 225)
    }

    /// 責務: 移動の境界(5 m)の少し外の 5.5 m では方位(北 0 度)を使い、少し内の 4.5 m では前の向きを保つことを確かめます。
    func testDisplacementBoundary() {
        let estimator = RoadRegulationHeadingEstimator()
        let moved = estimator.next(stateHeadingTenAtOrigin(), point: Points.point(x: 0, y: 5.5, course: nil, speed: 1))
        let notMoved = estimator.next(stateHeadingTenAtOrigin(), point: Points.point(x: 0, y: 4.5, course: nil, speed: 1))
        assertHeading(moved.headingDegrees, 0)
        assertHeading(notMoved.headingDegrees, 10)
    }

    /// 責務: 3 m しか動かない間は前の向きを保ち、基準点も動かさないので、続けて動いて基準点から 6 m になった所で方位を求めることを確かめます。
    ///
    /// 基準点(原点)→ 東へ 3 m(前の向き 10 度)→ 東へ 6 m(基準点からの方位 90 度)。基準点を 3 m の点へ動かしていれば
    /// 2点目からの移動は 3 m で、向きは 10 度のままになります。
    func testSmallMovesKeepHeadingAndAnchor() {
        let estimator = RoadRegulationHeadingEstimator()
        let first = estimator.next(stateHeadingTenAtOrigin(), point: Points.point(sequence: 1, x: 3, y: 0, course: nil, speed: 1))
        assertHeading(first.headingDegrees, 10)
        let second = estimator.next(first, point: Points.point(sequence: 2, x: 6, y: 0, course: nil, speed: 1))
        assertHeading(second.headingDegrees, 90)
    }

    /// 責務: 方位を求めたら基準点をいまの点に更新することを確かめます。
    ///
    /// 原点 → 北へ 6 m(方位 0 度。基準点は北 6 m)→ 東へ 6 m・北へ 6 m(新しい基準点からの方位 90 度)。
    /// 基準点が原点のままなら方位は 45 度になります。
    func testBearingUpdatesAnchorToCurrentPoint() {
        let estimator = RoadRegulationHeadingEstimator()
        let first = estimator.next(stateHeadingTenAtOrigin(), point: Points.point(sequence: 1, x: 0, y: 6, course: nil, speed: 1))
        assertHeading(first.headingDegrees, 0)
        let second = estimator.next(first, point: Points.point(sequence: 2, x: 6, y: 6, course: nil, speed: 1))
        assertHeading(second.headingDegrees, 90)
    }

    /// 責務: 初めの状態から、進行方向の無い点が続く時、最初の点からの移動が 5 m を超えるまで向きが nil で、超えたら方位になることを確かめます。
    func testHeadingFromInitialStateNeedsDisplacementFromFirstPoint() {
        let estimator = RoadRegulationHeadingEstimator()
        let first = estimator.next(.initial, point: Points.point(sequence: 0, x: 0, y: 0))
        let second = estimator.next(first, point: Points.point(sequence: 1, x: 0, y: -3))
        let third = estimator.next(second, point: Points.point(sequence: 2, x: 0, y: -6))
        XCTAssertNil(first.headingDegrees)
        XCTAssertNil(second.headingDegrees)
        assertHeading(third.headingDegrees, 180)
    }

    /// 責務: 進行方向が使える時は、基準点からの移動よりも進行方向を優先することを確かめます(北へ 6 m 動いても進行方向 200 度)。
    func testCourseTakesPriorityOverDisplacement() {
        let next = RoadRegulationHeadingEstimator().next(stateHeadingTenAtOrigin(), point: Points.point(x: 0, y: 6, course: 200, speed: 2))
        assertHeading(next.headingDegrees, 200)
    }

    /// 責務: 負の進行方向(CoreLocation の「無効」)と有限でない進行方向は、速さが十分でも使わず前の向きを保つことを確かめます。
    func testInvalidCourseIsNotUsed() {
        let estimator = RoadRegulationHeadingEstimator()
        let negative = estimator.next(stateHeadingTenAtOrigin(), point: Points.point(x: 0, y: 1, course: -1, speed: 2))
        let infinite = estimator.next(stateHeadingTenAtOrigin(), point: Points.point(x: 0, y: 1, course: .infinity, speed: 2))
        assertHeading(negative.headingDegrees, 10)
        assertHeading(infinite.headingDegrees, 10)
    }

    /// 責務: 360 度以上の進行方向は 360 で割った余り(370 → 10 度)にそろえることを確かめます。
    func testCourseIsNormalizedBelow360() throws {
        let next = RoadRegulationHeadingEstimator().next(.initial, point: Points.point(x: 0, y: 0, course: 370, speed: 2))
        XCTAssertEqual(try XCTUnwrap(next.headingDegrees), 10, accuracy: 0.01)
    }

    /// 責務: 進行方向を採った時も基準点をいまの点へ更新することを確かめます。
    ///
    /// 原点 → 北へ 4 m(進行方向 0 度を採り、基準点は北 4 m)→ (4, 4)・進行方向なし(新しい基準点から 4 m なので前の向き 0 度のまま)。
    /// 基準点が原点のままなら √32 ≈ 5.66 m の移動で方位 45 度になります。
    func testCourseUpdatesAnchor() {
        let estimator = RoadRegulationHeadingEstimator()
        let first = estimator.next(stateHeadingTenAtOrigin(), point: Points.point(sequence: 1, x: 0, y: 4, course: 0, speed: 2))
        let second = estimator.next(first, point: Points.point(sequence: 2, x: 4, y: 4, course: nil, speed: 1))
        assertHeading(first.headingDegrees, 0)
        assertHeading(second.headingDegrees, 0)
    }

    /// 責務: 進行方向を信じる速さのしきい値を 3 m/s に上げると、速さ 2 m/s の進行方向を使わないことを確かめます(埋め込みの数値でない)。
    func testCourseSpeedThresholdIsConfigurable() {
        var thresholds = RoadRegulationMatchingThresholds.standard
        thresholds.minimumCourseSpeedMetersPerSecond = 3
        let next = RoadRegulationHeadingEstimator(thresholds: thresholds)
            .next(stateHeadingTenAtOrigin(), point: Points.point(x: 0, y: 1, course: 123, speed: 2))
        assertHeading(next.headingDegrees, 10)
    }

    /// 責務: 方位を求める移動のしきい値を 10 m に上げると、6 m の移動では前の向きを保つことを確かめます(埋め込みの数値でない)。
    func testDisplacementThresholdIsConfigurable() {
        var thresholds = RoadRegulationMatchingThresholds.standard
        thresholds.minimumHeadingDisplacementMeters = 10
        let next = RoadRegulationHeadingEstimator(thresholds: thresholds)
            .next(stateHeadingTenAtOrigin(), point: Points.point(x: 6, y: 0, course: nil, speed: 1))
        assertHeading(next.headingDegrees, 10)
    }
}

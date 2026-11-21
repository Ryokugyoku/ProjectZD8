import Foundation

/// 軌跡の点の列から進む向きを推定します。
///
/// 次の順に決めます。
/// 1. 点の進行方向があり、GPS の速さが `minimumCourseSpeedMetersPerSecond` 以上 → 進行方向。基準点をいまの点にします。
/// 2. 基準点から `minimumHeadingDisplacementMeters` 以上動いた → 基準点からの方位。基準点をいまの点にします。
/// 3. どちらでもない → 前の向きをそのまま使います(初めは `nil`)。基準点が無ければいまの点を基準点にします。
nonisolated struct RoadRegulationHeadingEstimator: Sendable {
    /// しきい値です。
    private let thresholds: RoadRegulationMatchingThresholds
    /// 方位と距離の計算器です。
    private let distanceCalculator = GeoDistanceCalculator()

    /// しきい値を決めて推定器を作ります。
    ///
    /// 責務: 進行方向を信じる速さと、移動から向きを求める距離の基準を保持します。
    /// - Parameter thresholds: しきい値。
    init(thresholds: RoadRegulationMatchingThresholds = .standard) {
        self.thresholds = thresholds
    }

    /// 1点ぶん向きの推定を進めます。
    ///
    /// 責務: 進行方向・基準点からの方位・前の向きの順に向きを決め、新しい状態を返します。
    /// - Parameters:
    ///   - state: 直前の状態。
    ///   - point: いまの点。
    /// - Returns: 新しい状態。
    func next(_ state: RoadRegulationHeadingState, point: RoadRegulationTrackPoint) -> RoadRegulationHeadingState {
        if let course = reliableCourse(of: point) {
            return RoadRegulationHeadingState(headingDegrees: course, anchor: point.coordinate)
        }
        guard let anchor = state.anchor else {
            return RoadRegulationHeadingState(headingDegrees: state.headingDegrees, anchor: point.coordinate)
        }
        guard distanceCalculator.distanceMeters(anchor, point.coordinate) >= thresholds.minimumHeadingDisplacementMeters,
              let bearing = distanceCalculator.bearingDegrees(from: anchor, to: point.coordinate)
        else { return state }
        return RoadRegulationHeadingState(headingDegrees: bearing, anchor: point.coordinate)
    }

    /// 点の進行方向が信じられる時に、その値を 0..<360 にそろえて返します。
    ///
    /// 責務: 進行方向が有限で負でなく、GPS の速さが有限でしきい値以上の時だけ進行方向を採ります。
    /// - Parameter point: いまの点。
    /// - Returns: 進行方向(度)。信じられなければ `nil`。
    private func reliableCourse(of point: RoadRegulationTrackPoint) -> Double? {
        guard let course = point.courseDegrees, course.isFinite, course >= 0,
              let speed = point.gpsSpeedMetersPerSecond, speed.isFinite,
              speed >= thresholds.minimumCourseSpeedMetersPerSecond
        else { return nil }
        return course.truncatingRemainder(dividingBy: 360)
    }
}

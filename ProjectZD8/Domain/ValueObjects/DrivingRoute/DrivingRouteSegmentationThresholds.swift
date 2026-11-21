import Foundation

/// 軌跡を区間に分ける時のしきい値です。段階3(詳細の地図)と段階4(解析)で共通に使います。
nonisolated struct DrivingRouteSegmentationThresholds: Equatable, Sendable {
    /// 標準のしきい値です(正確 10 s・50 m、概略 1,200 s・5,000 m、位置の飛び 90 m/s)。
    static let standard = DrivingRouteSegmentationThresholds(
        preciseMaximumGapSeconds: 10,
        approximateMaximumGapSeconds: 1_200,
        preciseMaximumHorizontalAccuracyMeters: 50,
        approximateMaximumHorizontalAccuracyMeters: 5_000,
        maximumImpliedSpeedMetersPerSecond: 90
    )

    /// 正確な位置の区間で、隣り合う点をつなぐ最大の時間差(秒、ちょうどはつなぐ)です。
    let preciseMaximumGapSeconds: TimeInterval
    /// 概略の位置の区間で、隣り合う点をつなぐ最大の時間差(秒、ちょうどはつなぐ)です。
    let approximateMaximumGapSeconds: TimeInterval
    /// 正確な位置で残す最大の水平精度(m、ちょうどは残す)です。
    let preciseMaximumHorizontalAccuracyMeters: Double
    /// 概略の位置で残す最大の水平精度(m、ちょうどは残す)です。
    let approximateMaximumHorizontalAccuracyMeters: Double
    /// 隣り合う点の「距離 ÷ 時間差」の上限(m/s、ちょうどは残す)です。超えたら位置の飛びとして切ります。
    let maximumImpliedSpeedMetersPerSecond: Double
}

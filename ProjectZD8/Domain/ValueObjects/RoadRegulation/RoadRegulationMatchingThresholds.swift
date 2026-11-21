import Foundation

/// 規制の当てはめと判定に使うしきい値です。`standard` が設計どおりの初期値で、テストでは個別の値を差し替えられます。
nonisolated struct RoadRegulationMatchingThresholds: Equatable, Sendable {
    /// 設計どおりの初期値です。
    static let standard = RoadRegulationMatchingThresholds()

    // MARK: 候補と精度

    /// 周辺の規制を探す半径(m)。
    var searchRadiusMeters = 120.0
    /// これを超える水平精度(m)の点は使わない。
    var maximumUsableHorizontalAccuracyMeters = 50.0
    /// 横方向の許容の基本値(m)。許容 = clamp(基本値 + 精度, 最小, 最大)。
    var lateralToleranceBaseMeters = 12.0
    /// 横方向の許容の最小値(m)。
    var lateralToleranceMinimumMeters = 15.0
    /// 横方向の許容の最大値(m)。
    var lateralToleranceMaximumMeters = 35.0
    /// いま乗っている規制を長く残す幅(m)。
    var exitHysteresisMeters = 10.0
    /// 向きが合うとみなす角度差の上限(度)。
    var headingAlignmentDegrees = 40.0
    /// 逆向きとみなす角度差の下限(度)。
    var reverseHeadingDegrees = 140.0
    /// 角度差1度あたりの点数の不利(m)。
    var headingPenaltyMetersPerDegree = 0.2
    /// いま乗っている候補の点数の有利(m)。
    var currentRegulationBonusMeters = 5.0
    /// 1位と2位の点数差がこれ未満で結果が違えば曖昧とする(m)。
    var ambiguityMarginMeters = 3.0
    /// 状態の切り替えに必要な、同じ観測が続く点数。
    var confirmationPoints = 3
    /// これを超えて使える点が無ければ記録の空白とする(秒)。
    var maximumTrackGapSeconds = 10.0
    /// これ未満の GPS の速さでは進行方向を信じない(m/s)。
    var minimumCourseSpeedMetersPerSecond = 1.5
    /// 移動から向きを求める最小の距離(m)。
    var minimumHeadingDisplacementMeters = 5.0
    /// これを超える長さの線分を粗いとみなす(m)。
    var coarseSegmentLengthMeters = 1_000.0
    /// 粗い線分からこの距離以内なら判定できないとする(m)。
    var coarseCorridorMeters = 100.0
    /// 区域の境目からこの距離未満なら判定できないとする(m)。
    var zoneBoundaryMarginMeters = 20.0

    // MARK: 最高速度

    /// 速度の許容の最小値(km/h)。許容 = max(最小値, ceil(制限 × 割合))。
    var speedToleranceMinimumKph = 3.0
    /// 速度の許容の、制限値に対する割合。
    var speedToleranceFraction = 0.05
    /// 超過とみなす連続の最短の長さ(秒)。
    var minimumExceedDurationSeconds = 2.0
    /// 超過が続いているとみなすサンプルの間隔の上限(秒)。
    var maximumExceedRunGapSeconds = 3.0
    /// 制限内と言い切るのに必要な車速の取得間隔の上限(秒)。
    var maximumSpeedSampleGapSeconds = 5.0
    /// 超過量がこれ以上なら別の道路の疑いとして判定できないとする(km/h)。
    var implausibleExcessKph = 40.0

    // MARK: 一時停止

    /// 停止点の手前で接近として追う長さ(m)。
    var stopApproachLengthMeters = 40.0
    /// 停止点のこの距離手前まで来たら到達とする(m)。
    var stopReachMeters = 5.0
    /// 一時停止の横方向の許容の基本値(m)。許容 = clamp(基本値 + 精度, 最小, 最大)。
    var stopLateralToleranceBaseMeters = 8.0
    /// 一時停止の横方向の許容の最小値(m)。
    var stopLateralToleranceMinimumMeters = 10.0
    /// 一時停止の横方向の許容の最大値(m)。
    var stopLateralToleranceMaximumMeters = 20.0
    /// 接近を始める時の角度差の上限(度)。
    var stopHeadingDegrees = 45.0
    /// 接近の範囲からこれ以上外れたら打ち切る(m)。
    var stopAbandonExtraMeters = 10.0
    /// 接近中にこの角度差を超えたら打ち切る(度)。
    var stopAbandonHeadingDegrees = 90.0
    /// 停止点と進入方向の点がこれより近い進入方向は追わない(m)。
    var minimumStopApproachVectorMeters = 2.0
    /// 停止したとみなす車速の上限(km/h)。
    var stoppedSpeedKph = 0.5
    /// 停止の証拠を探す窓を開始・到達の前後へ広げる幅(秒)。
    var stopEvidenceMarginSeconds = 1.0
    /// 接近の前後の車速がこの時間内にあること(秒)。
    var stopBracketMaximumSeconds = 3.0
    /// 停止して再び発進するのに想定する最大の減速度(m/s²)。
    var maximumDecelerationMps2 = 5.0
    /// 一度到達した停止点を、ここまで離れたら再び検出する(m)。
    var stopRearmDistanceMeters = 60.0

    // MARK: 一方通行・徐行

    /// 逆走とみなすのに必要な距離(m)。区間が短い時は `wrongWayRequiredDistance` で小さくなる。
    var wrongWayMinimumDistanceMeters = 50.0
    /// 短い区間で必要な距離の下限(m)。
    var wrongWayShortSectionMinimumMeters = 20.0
    /// 短い区間で必要な距離の、区間長に対する割合。
    var wrongWayShortSectionFraction = 0.8
    /// 逆走の距離に数える点の水平精度の上限(m)。
    var wrongWayMaximumAccuracyMeters = 20.0
    /// 徐行の参考の速さ(km/h)。
    var slowDownReferenceKph = 10.0

    /// 線の規制に対する横方向の許容を返します。
    ///
    /// 責務: clamp(基本値 + 精度, 最小, 最大) を計算します。
    /// - Parameter accuracy: 点の水平精度(m)。
    /// - Returns: 横方向の許容(m)。
    func lateralTolerance(accuracy: Double) -> Double {
        Self.clamp(lateralToleranceBaseMeters + accuracy, lateralToleranceMinimumMeters, lateralToleranceMaximumMeters)
    }

    /// 一時停止に対する横方向の許容を返します。
    ///
    /// 責務: clamp(基本値 + 精度, 最小, 最大) を計算します。
    /// - Parameter accuracy: 点の水平精度(m)。
    /// - Returns: 横方向の許容(m)。
    func stopLateralTolerance(accuracy: Double) -> Double {
        Self.clamp(
            stopLateralToleranceBaseMeters + accuracy,
            stopLateralToleranceMinimumMeters,
            stopLateralToleranceMaximumMeters
        )
    }

    /// 最高速度に対する速度の許容を返します。
    ///
    /// 責務: max(最小値, ceil(制限 × 割合)) を計算します(L=40 なら 3、L=80 なら 4)。
    /// - Parameter limitKph: 制限速度(km/h)。
    /// - Returns: 速度の許容(km/h)。
    func speedTolerance(limitKph: Int) -> Double {
        Swift.max(speedToleranceMinimumKph, (Double(limitKph) * speedToleranceFraction).rounded(.up))
    }

    /// 逆走とみなすのに必要な距離を返します。
    ///
    /// 責務: min(既定の距離, max(短い区間の下限, 割合 × 区間長)) を計算します。
    /// - Parameter regulationLengthMeters: 規制区間の長さ(m)。
    /// - Returns: 必要な距離(m)。
    func wrongWayRequiredDistance(regulationLengthMeters: Double) -> Double {
        Swift.min(
            wrongWayMinimumDistanceMeters,
            Swift.max(wrongWayShortSectionMinimumMeters, wrongWayShortSectionFraction * regulationLengthMeters)
        )
    }

    /// 値を範囲へ切り詰めます。
    ///
    /// 責務: 下限と上限の間に収めます。
    /// - Parameters:
    ///   - value: 元の値。
    ///   - lower: 下限。
    ///   - upper: 上限。
    /// - Returns: 切り詰めた値。
    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        Swift.min(Swift.max(value, lower), upper)
    }
}

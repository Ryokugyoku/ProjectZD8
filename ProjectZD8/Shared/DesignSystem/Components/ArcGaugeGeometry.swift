import Foundation

/// 270°ゲージの値→割合→角度の対応を計算する純粋ロジック。
///
/// 角度は SwiftUI の座標系(0° = 3時方向、時計回りが正)で、開始は 135°(7時半)、終了は 405°(4時半)。
nonisolated enum ArcGaugeGeometry {
    /// 弧の開始角(度)。
    static let startDegrees: Double = 135
    /// 弧の掃引角(度)。
    static let sweepDegrees: Double = 270

    /// 値をレンジ内の 0...1 の割合に変換する。
    ///
    /// 責務: 欠損・非有限値・幅ゼロのレンジは nil、範囲外はクランプした割合を返す。
    static func fraction(value: Double?, range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite, range.lowerBound.isFinite, range.upperBound.isFinite else { return nil }
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return nil }
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    /// 割合に対応する絶対角度(度)を返す。
    ///
    /// 責務: 0...1 にクランプした割合を開始角からの角度へ写像する。
    static func degrees(forFraction fraction: Double) -> Double {
        startDegrees + sweepDegrees * min(1, max(0, fraction))
    }

    /// 警告ゾーンをレンジ内の割合区間へ変換する。
    ///
    /// 責務: レンジと重ならない・不正なゾーンは nil、重なる部分はクランプして返す。
    static func zoneFractions(zone: ClosedRange<Double>?, range: ClosedRange<Double>) -> ClosedRange<Double>? {
        guard let zone, range.upperBound > range.lowerBound,
              zone.upperBound >= range.lowerBound, zone.lowerBound <= range.upperBound,
              let lower = fraction(value: zone.lowerBound, range: range),
              let upper = fraction(value: zone.upperBound, range: range),
              upper > lower
        else { return nil }
        return lower...upper
    }
}

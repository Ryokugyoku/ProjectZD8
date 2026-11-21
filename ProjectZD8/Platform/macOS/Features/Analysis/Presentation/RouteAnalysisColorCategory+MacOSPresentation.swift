#if os(macOS)
import SwiftUI

/// 解析の地図の線の色の分類へ、macOS で描く色・太さ・線の種類を付加します。
extension RouteAnalysisColorCategory {
    /// 線と凡例の色見本の色です。
    ///
    /// 責務: 基本はアクセントのシアン、段は `SequentialColorRamp`、値なしは灰色、色調は色調ごとの色に対応させます。
    var color: Color {
        switch self {
        case .base: .cyan
        case .ramp(let step): SequentialColorRamp.color(step: step)
        case .noValue: .gray
        case .tone(let tone): Self.toneColor(tone)
        }
    }

    /// 破線で描く時に `true` です。値なしの区間だけ破線にします。
    var isDashed: Bool {
        self == .noValue
    }

    /// 線の太さ(pt)です。
    ///
    /// 責務: 既定の太さに、段の番号ごとに `MacOSRouteAnalysisMetrics.rampWidthIncrement` を足します(段以外は既定の太さ)。
    var lineWidth: CGFloat {
        guard case .ramp(let step) = self else { return RouteMapMetrics.lineWidth }
        let clampedStep = min(max(step, 0), SequentialColorRamp.stepCount - 1)
        return RouteMapMetrics.lineWidth + CGFloat(clampedStep) * MacOSRouteAnalysisMetrics.rampWidthIncrement
    }

    /// 重ね合わせの色調の色を返します。
    ///
    /// 責務: 色調ごとの色に対応させます。オレンジは注意(短い区間)に限ります。
    /// - Parameter tone: 重ね合わせの色調。
    /// - Returns: 色調の色。
    private static func toneColor(_ tone: RouteAnalysisTone) -> Color {
        switch tone {
        case .positive: .green
        case .neutral: .secondary
        case .caution: .orange
        case .critical: .red
        case .unknown: .gray
        }
    }
}
#endif

import SwiftUI

/// 明度が単調に下がる寒色の5段の連続色です。機能の知識を持たない汎用の色の段階です。
enum SequentialColorRamp {
    /// 段の数です。
    static let stepCount = 5

    /// 淡いシアンから濃い紫までの5段の色です。
    private static let steps: [Color] = [
        Color(red: 0x9E / 255, green: 0xDC / 255, blue: 0xE6 / 255),
        Color(red: 0x3F / 255, green: 0xC1 / 255, blue: 0xD6 / 255),
        Color(red: 0x1E / 255, green: 0x88 / 255, blue: 0xC8 / 255),
        Color(red: 0x3A / 255, green: 0x4F / 255, blue: 0xB0 / 255),
        Color(red: 0x5B / 255, green: 0x2A / 255, blue: 0x86 / 255)
    ]

    /// 段の番号に対応する色を返します。
    ///
    /// 責務: 0〜4の段の番号を色へ引き、範囲外の番号は端の色へ切り詰めます。
    /// - Parameter step: 段の番号。小さいほど淡い色です。
    /// - Returns: 段の色。
    static func color(step: Int) -> Color {
        steps[min(max(step, 0), stepCount - 1)]
    }
}

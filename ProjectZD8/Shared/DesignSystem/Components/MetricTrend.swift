import SwiftUI

/// 計測値の傾向表示(方向+呼び出し側がローカライズした説明文)。
struct MetricTrend {
    /// 傾向の向き。
    enum Direction {
        case up
        case down
        case steady

        /// 向きを示す SF Symbol 名。
        var symbol: String {
            switch self {
            case .up: "arrow.up.right"
            case .down: "arrow.down.right"
            case .steady: "arrow.right"
            }
        }
    }

    /// 傾向の向き。
    var direction: Direction
    /// ローカライズ済みの説明(例: 「+3.2」)。
    var text: Text
    /// 強調トーン。向きの良し悪しは呼び出し側が決める。
    var tone: StatusTone

    /// 傾向を作る。
    ///
    /// 責務: 向き・説明・トーンを束ねる。
    init(_ direction: Direction, text: Text, tone: StatusTone = .neutral) {
        self.direction = direction
        self.text = text
        self.tone = tone
    }
}

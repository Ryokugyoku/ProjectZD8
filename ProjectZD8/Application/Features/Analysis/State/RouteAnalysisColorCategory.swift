/// 地図の線の色の分類です。OS ごとの Presentation が実際の色と線の種類へ写します。
nonisolated enum RouteAnalysisColorCategory: Hashable, Sendable {
    /// 色分けしない時の基本の色(アクセント)。
    case base
    /// 値の区分による連続色の段(0 始まり)。
    case ramp(step: Int)
    /// 対応する値が無い区間(灰色の破線)。
    case noValue
    /// 重ね合わせの色調。
    case tone(RouteAnalysisTone)
}

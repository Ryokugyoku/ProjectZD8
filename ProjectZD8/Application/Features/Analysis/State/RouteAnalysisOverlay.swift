import Foundation

/// 走行ルートに重ねる分類(5c の判定結果など)です。同じ Analysis Feature の State がこの値を直接作ります。
nonisolated struct RouteAnalysisOverlay: Identifiable, Equatable, Sendable {
    /// 重ね合わせを識別する文字列です。
    let id: String
    /// 選択肢に出す名前のローカライズキーです。
    let titleKey: String
    /// 位置の連番の範囲ごとの色の分類です。
    let runs: [RouteAnalysisColorRun]
    /// 凡例の項目です。
    let legend: [RouteAnalysisLegendEntry]
    /// グラフで強調する時刻の範囲です。
    let highlightedTimeRanges: [ClosedRange<Date>]
}

import Foundation

/// 交通規制の照合の一覧の1行です。文字列は表示用に解決済み、またはローカライズキーです。
nonisolated struct SessionRoadRegulationReviewRow: Identifiable, Equatable, Sendable {
    /// 並べた後の位置(0 始まり)です。
    let id: Int
    /// 規制の種類です。
    let kind: SessionRoadRegulationReviewKind
    /// 判定の分類です。
    let outcome: SessionRoadRegulationReviewOutcome
    /// 色見本と地図の色の分類です。
    let category: RouteAnalysisColorCategory
    /// 判定の文言のローカライズキーです(判定できない時は理由のキー)。
    let titleKey: String
    /// 行に添える SF Symbols の名前です。
    let systemImage: String
    /// 時刻の文字列です(例 `10:21:05–10:21:40`)。
    let timeText: String
    /// 数値の文字列(解決済み)です。空のこともあります。
    let figureTexts: [String]
    /// 区間の時刻の範囲(位置の観測時刻。余白なし)です。
    let timeRange: ClosedRange<Date>
    /// 区間の位置サンプルの連番の範囲です。
    let sequenceRange: ClosedRange<Int64>
    /// 判定できない理由です。判定できた時は `nil` です。
    let undeterminedReason: RoadRegulationUndeterminedReason?
    /// この行の種類の重ね合わせの ID です。
    let overlayID: String
}

import Foundation

/// 交通規制の照合に添える出典と注意書きの内容です。
nonisolated struct SessionRoadRegulationReviewAttribution: Equatable, Sendable {
    /// 注意書きのローカライズキーです(常に出します)。
    static let disclaimerKey = "road_regulation.attribution.disclaimer"
    /// 出典のローカライズキーです。
    static let sourceKey = "road_regulation.attribution.source"
    /// 加工した旨のローカライズキーです。
    static let processedKey = "road_regulation.attribution.processed"
    /// 使用したデータの見出しのローカライズキーです。
    static let datasetsTitleKey = "analysis.road_regulation.attribution.datasets_title"
    /// 照合の結果が無い時の内容です。
    static let empty = SessionRoadRegulationReviewAttribution(datasetTexts: [], usedOnText: nil, sourceURL: nil)

    /// 使用した版の文字列(解決済み。例「沖縄県(基準月 2026年9月)」)です。
    let datasetTexts: [String]
    /// 利用日の文字列(解決済み)です。利用日が分からない時は `nil` です。
    let usedOnText: String?
    /// 規制データの配布ページの URL です。
    let sourceURL: URL?
}

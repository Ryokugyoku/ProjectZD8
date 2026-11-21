import Foundation

/// 照合の結果から一度だけ作る表示の内容です。メインスレッドの外で作ります。
nonisolated struct SessionRoadRegulationReviewContent: Equatable, Sendable {
    /// 並べた後の全行です。
    let rows: [SessionRoadRegulationReviewRow]
    /// 種類ごとのまとめです。
    let summaries: [SessionRoadRegulationReviewKindSummary]
    /// 添える注記です。
    let notices: [SessionRoadRegulationReviewNotice]
    /// 出典と注意書きです。
    let attribution: SessionRoadRegulationReviewAttribution
}

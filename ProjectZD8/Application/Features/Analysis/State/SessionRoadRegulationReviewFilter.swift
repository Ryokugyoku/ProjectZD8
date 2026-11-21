import Foundation

/// 交通規制の照合の一覧に出す行の絞り込みです。
nonisolated enum SessionRoadRegulationReviewFilter: String, CaseIterable, Identifiable, Sendable {
    /// 確認が必要な区間(可能性あり・判定できない)だけを出します。
    case attention
    /// すべての区間を出します。
    case all

    /// Picker で使用する安定識別子です。
    var id: String { rawValue }

    /// 絞り込みの名前のローカライズキーです。View で `LocalizedStringKey` に変換します。
    var titleKey: String {
        switch self {
        case .attention: "analysis.road_regulation.filter.attention"
        case .all: "analysis.road_regulation.filter.all"
        }
    }

    /// 判定の分類がこの絞り込みで表示されるかどうかを返します。
    ///
    /// 責務: `attention` は可能性あり・判定できないだけを、`all` はすべてを表示の対象と判定します。
    /// - Parameter outcome: 判定の分類。
    /// - Returns: 表示する時は `true`。
    func includes(_ outcome: SessionRoadRegulationReviewOutcome) -> Bool {
        switch self {
        case .attention: outcome == .possibleIssue || outcome == .undeterminable
        case .all: true
        }
    }
}

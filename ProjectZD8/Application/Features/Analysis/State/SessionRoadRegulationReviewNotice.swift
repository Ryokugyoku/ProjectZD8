import Foundation

/// 交通規制の照合に添える注記です。宣言の順に並べます。
nonisolated enum SessionRoadRegulationReviewNotice: String, CaseIterable, Identifiable, Sendable {
    /// 車速の記録が iCloud にあり、取得すると判定できます。
    case speedInCloud
    /// 車速の記録が無いため、車速を使う規制は判定できません。
    case speedNotRecorded
    /// 取得済みの規制データの範囲外を走行した区間があります。
    case outsideData
    /// 「指定なし」の意味の説明です。
    case unregulatedExplained

    /// 一覧で使用する安定識別子です。
    var id: String { rawValue }

    /// 注記の文言のローカライズキーです。View で `LocalizedStringKey` に変換します。
    var textKey: String {
        switch self {
        case .speedInCloud: "analysis.road_regulation.notice.speed_in_cloud"
        case .speedNotRecorded: "analysis.road_regulation.notice.speed_not_recorded"
        case .outsideData: "analysis.road_regulation.notice.outside_data"
        case .unregulatedExplained: "analysis.road_regulation.notice.unregulated_explained"
        }
    }
}

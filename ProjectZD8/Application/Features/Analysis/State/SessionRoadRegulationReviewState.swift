import Foundation

/// 交通規制の照合を画面へ公開する状態です。
nonisolated struct SessionRoadRegulationReviewState: Equatable, Sendable {
    /// 照合の対象のセッションの ID です。表示していない時は `nil` です。
    var sessionID: ConnectionSessionID?
    /// 表示の段階です。
    var status: SessionRoadRegulationReviewStatus = .idle
    /// 種類ごとのまとめです。
    var summaries: [SessionRoadRegulationReviewKindSummary] = []
    /// 種類ごとの一覧です。
    var sections: [SessionRoadRegulationReviewSection] = []
    /// 添える注記です。
    var notices: [SessionRoadRegulationReviewNotice] = []
    /// 出典と注意書きです。
    var attribution: SessionRoadRegulationReviewAttribution = .empty
    /// 一覧の絞り込みです。
    var filter: SessionRoadRegulationReviewFilter = .attention
    /// 選んでいる行の ID です。選んでいない時は `nil` です。
    var selectedRowID: Int?
    /// 走行ルートの表示へ送る重ね合わせです。
    var overlays: [RouteAnalysisOverlay] = []
}

import Foundation

/// 交通規制データの出典の表示です(データ名・提供元・ページ・利用日・「加工して作成」・注意書き)。
nonisolated struct RoadRegulationAttribution: Equatable, Sendable {
    /// 出典(データ名「交通規制情報」と、提供元の公益財団法人日本道路交通情報センター(JARTIC))の文言キー。
    static let sourceKey = "road_regulation.attribution.source"
    /// 配布ページの URL。
    static let sourceURLString = "https://www.jartic.or.jp/service/opendata/"
    /// 利用日の文言キー(日付を差し込む)。
    static let usedOnKey = "road_regulation.attribution.used_on"
    /// 「加工して作成」の文言キー。
    static let processedKey = "road_regulation.attribution.processed"
    /// データが実際の規制と一致しないことがある旨の注意書きの文言キー。
    static let disclaimerKey = "road_regulation.attribution.disclaimer"

    /// 利用日(取得済みの版の中で最新の取得日時)。取得済みが無ければ `nil`。
    let usedOn: Date?

    /// 取得済みの版から出典の表示を作ります。
    ///
    /// 責務: 取得日時の最大を利用日にします。
    /// - Parameter datasets: 取得済みの版。
    init(datasets: [RoadRegulationDataset]) {
        usedOn = datasets.map(\.downloadedAt).max()
    }
}

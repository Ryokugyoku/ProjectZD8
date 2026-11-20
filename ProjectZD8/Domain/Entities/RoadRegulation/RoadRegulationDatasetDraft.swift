import Foundation

/// 取り込みを始める版の情報(取り込み前に分かっているもの)です。
nonisolated struct RoadRegulationDatasetDraft: Equatable, Sendable {
    /// 都道府県。
    let prefecture: JapanesePrefectureCode
    /// 配布の公開時刻の印(12桁。例 "202611010000")。
    let publicationStamp: String
    /// ZIP の取得元 URL。
    let sourceURL: URL
    /// ZIP を受け取った時刻。
    let downloadedAt: Date
}

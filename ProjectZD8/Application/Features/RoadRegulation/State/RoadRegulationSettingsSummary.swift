import Foundation

/// 設定画面のカードに出す、交通規制データのまとめです。
nonisolated struct RoadRegulationSettingsSummary: Equatable, Sendable {
    /// 取得済みの都道府県の数。
    let downloadedCount: Int
    /// 取得済みの版の中で最も古い基準月。取得済みが無ければ `nil`。
    let oldestDataMonth: RoadRegulationDataMonth?
    /// 取得済みの版の中で最も新しい取得日時。取得済みが無ければ `nil`。
    let latestDownloadedAt: Date?
    /// どれかの県を取り込み中か。
    let isImporting: Bool

    /// まとめの文言キー。取得済みが無ければ `summary.none`、あれば `summary.count`(件数と最も古い基準月を差し込む)。
    var summaryKey: String {
        downloadedCount == 0 ? "road_regulation.settings.summary.none" : "road_regulation.settings.summary.count"
    }
}

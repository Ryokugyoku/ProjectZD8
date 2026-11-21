import Foundation

/// 設計書 §6 の A11 の注に挙がっている、交通規制の画面の文言キーの一覧です(テストの期待値。製品のコードから写していません)。
nonisolated enum RoadRegulationSettingsKeyCatalog {
    /// 責務: 接頭辞と名前の列からキーを作ります。
    private static func keys(_ prefix: String, _ names: [String]) -> [String] {
        names.map { "\(prefix).\($0)" }
    }

    /// 取り込みのエラーごとのキー(`road_regulation.error.<snake_case>`)です。
    static let errorKeys = keys("road_regulation.error", [
        "catalog_unavailable", "catalog_format_changed", "prefecture_not_in_catalog", "download_failed", "archive_invalid",
        "csv_format_changed", "no_regulations_in_archive", "insufficient_storage", "storage_unavailable",
    ])

    /// 状態のキーです。
    static let statusKeys = keys("road_regulation.status", [
        "not_downloaded", "downloaded", "update_available", "importing", "failed_keeps_previous",
    ])

    /// 段階のキーです。
    static let phaseKeys = keys("road_regulation.phase", [
        "preparing", "fetching_catalog", "downloading", "importing", "activating", "cleaning_up",
    ])

    /// 出典のキーです。
    static let attributionKeys = keys("road_regulation.attribution", ["source", "used_on", "processed", "disclaimer"])

    /// 都道府県名のキー(`road_regulation.prefecture.01`〜`47`)です。
    static let prefectureKeys = (1...47).map { String(format: "road_regulation.prefecture.%02d", $0) }

    /// A11 の注のキーのすべてです。
    static var all: Set<String> {
        let settings = keys("road_regulation.settings", ["eyebrow", "title", "description", "manage", "summary.none", "summary.count"])
        let data = keys("road_regulation.data", [
            "title", "check_updates", "checking", "checked", "download", "update", "remove", "cancel",
            "remove_confirm.title", "remove_confirm.message", "remove_confirm.confirm",
        ])
        let detail = keys("road_regulation.detail", ["data_month", "count", "rejected", "downloaded_at"])
        return Set(settings + data + statusKeys + phaseKeys + detail + errorKeys + attributionKeys + prefectureKeys)
    }
}

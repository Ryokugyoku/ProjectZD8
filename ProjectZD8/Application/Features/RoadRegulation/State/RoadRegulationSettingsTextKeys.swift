import Foundation

/// 交通規制データの管理画面の文言キーを選ぶ純粋型です(キーだけを返し、View で `LocalizedStringKey` に変換します)。
nonisolated struct RoadRegulationSettingsTextKeys: Sendable {
    /// 状態を持たない型を作ります。
    ///
    /// 責務: 文言キーの選択器を構築します。
    init() {}

    /// 都道府県の行の状態の文言キーを選びます。
    ///
    /// 責務: 取り込み中 → 失敗して前の版を使用中 → 更新あり → 取得済み → 未取得の順に状態を決めます。
    /// 失敗して前の版が無い時は「未取得」です(失敗の内容は別にエラーとして出します)。
    /// - Parameter row: 都道府県の行。
    /// - Returns: `road_regulation.status.*` のキー。
    func statusKey(for row: RoadRegulationPrefectureRow) -> String {
        if row.activeImport != nil { return "road_regulation.status.importing" }
        guard row.dataset != nil else { return "road_regulation.status.not_downloaded" }
        if row.lastFailure != nil { return "road_regulation.status.failed_keeps_previous" }
        return row.isUpdateAvailable ? "road_regulation.status.update_available" : "road_regulation.status.downloaded"
    }

    /// 取得ボタンの文言キーを選びます。
    ///
    /// 責務: 未取得なら「取得」、取得済みなら「更新」を選びます。
    /// - Parameter row: 都道府県の行。
    /// - Returns: `road_regulation.data.download` か `road_regulation.data.update`。
    func downloadButtonKey(for row: RoadRegulationPrefectureRow) -> String {
        row.dataset == nil ? "road_regulation.data.download" : "road_regulation.data.update"
    }

    /// 取り込みの段階の文言キーを選びます。
    ///
    /// 責務: 段階の種類ごとにキーを返します(進捗の値は見ません)。
    /// - Parameter phase: 取り込みの段階。
    /// - Returns: `road_regulation.phase.*` のキー。
    func phaseKey(for phase: RoadRegulationImportPhase) -> String {
        switch phase {
        case .preparing: "road_regulation.phase.preparing"
        case .fetchingCatalog: "road_regulation.phase.fetching_catalog"
        case .downloading: "road_regulation.phase.downloading"
        case .importing: "road_regulation.phase.importing"
        case .activating: "road_regulation.phase.activating"
        case .cleaningUp: "road_regulation.phase.cleaning_up"
        }
    }

    /// 取り込みのエラーの文言キーを選びます。
    ///
    /// 責務: エラーの種類を snake_case にしたキーを返します。
    /// - Parameter error: 取り込みのエラー。
    /// - Returns: `road_regulation.error.<snake_case>` のキー。
    func errorKey(for error: RoadRegulationImportError) -> String {
        "road_regulation.error." + Self.errorNames[error, default: "storage_unavailable"]
    }

    /// 一覧の確認の状態の文言キーを選びます。
    ///
    /// 責務: 未確認は「更新を確認」、確認中・確認済みはその状態、失敗はエラーのキーを返します。
    /// - Parameter status: 一覧の確認の状態。
    /// - Returns: 文言キー。
    func catalogStatusKey(for status: RoadRegulationCatalogCheckStatus) -> String {
        switch status {
        case .notChecked: "road_regulation.data.check_updates"
        case .checking: "road_regulation.data.checking"
        case .checked: "road_regulation.data.checked"
        case let .failed(error): errorKey(for: error)
        }
    }

    /// エラーの種類ごとの snake_case の名前。
    private static let errorNames: [RoadRegulationImportError: String] = [
        .catalogUnavailable: "catalog_unavailable",
        .catalogFormatChanged: "catalog_format_changed",
        .prefectureNotInCatalog: "prefecture_not_in_catalog",
        .downloadFailed: "download_failed",
        .archiveInvalid: "archive_invalid",
        .csvFormatChanged: "csv_format_changed",
        .noRegulationsInArchive: "no_regulations_in_archive",
        .insufficientStorage: "insufficient_storage",
        .storageUnavailable: "storage_unavailable"
    ]
}

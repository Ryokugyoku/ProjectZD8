import Foundation

/// 交通規制データの配布元から一覧と ZIP を取得する能力です。
///
/// 投げるのは `RoadRegulationImportError` か `CancellationError` だけです。
nonisolated protocol RoadRegulationSourcePort: Sendable {
    /// 配布の一覧を取得します。
    ///
    /// 責務: 一覧を取得して解読し、都道府県ごとの ZIP を返します。
    /// - Returns: 配布の一覧。
    /// - Throws: `.catalogUnavailable` / `.catalogFormatChanged`、または `CancellationError`。
    func currentCatalog() async throws -> RoadRegulationCatalog

    /// ZIP をダウンロードします。
    ///
    /// 責務: 一覧の項目の ZIP を受け取り、一時フォルダへ置いてその場所を返します。
    /// - Parameters:
    ///   - entry: ダウンロードする項目。
    ///   - progress: 受け取りの進み具合の通知。
    /// - Returns: 受け取った ZIP のファイル URL。
    /// - Throws: `.downloadFailed` / `.insufficientStorage`、または `CancellationError`。
    func downloadArchive(
        for entry: RoadRegulationCatalogEntry,
        progress: @escaping @Sendable (RoadRegulationTransferProgress) -> Void
    ) async throws -> URL

    /// 受け取った ZIP を消します。
    ///
    /// 責務: 指定した一時ファイルを消します。失敗は無視し、診断だけを残します。
    /// - Parameter url: 消す ZIP。
    func removeDownloadedArchive(at url: URL)

    /// 残っている一時 ZIP をすべて消します。
    ///
    /// 責務: 以前の取り込みで残ったダウンロード済みファイルを掃除します。
    func removeLeftoverDownloads()
}

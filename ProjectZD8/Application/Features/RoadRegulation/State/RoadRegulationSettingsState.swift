import Foundation

/// 交通規制データの管理画面の状態と、その遷移の規則です(SwiftUI に依存しない純粋型)。
///
/// - 行は常に47件(都道府県コードの昇順)です。
/// - 同時に取り込めるのは1県だけです。取り込み中は、ほかの行の取得・削除を押せません。
/// - 「更新あり」は、確かめた一覧の公開の印が手元の版と違う時です。
/// - 取り込みに失敗しても手元の版は残し、行に失敗を記録して画面にエラーを出します。
nonisolated struct RoadRegulationSettingsState: Equatable, Sendable {
    /// 都道府県の行(常に47件)。
    var rows: [RoadRegulationPrefectureRow]
    /// 一覧の確認の状態。
    var catalogStatus: RoadRegulationCatalogCheckStatus
    /// 取り込み中の県。取り込み中でなければ `nil`。
    var importingPrefecture: JapanesePrefectureCode?
    /// 削除の確認を出している県。
    var pendingRemoval: JapanesePrefectureCode?
    /// 画面に出しているエラー。
    var presentedError: RoadRegulationImportError?

    /// 設定画面のカードに出すまとめ。
    var summary: RoadRegulationSettingsSummary {
        let datasets = rows.compactMap(\.dataset)
        return RoadRegulationSettingsSummary(
            downloadedCount: datasets.count,
            oldestDataMonth: datasets.map(\.dataMonth).min(),
            latestDownloadedAt: datasets.map(\.downloadedAt).max(),
            isImporting: importingPrefecture != nil
        )
    }

    /// 出典の表示。
    var attribution: RoadRegulationAttribution {
        RoadRegulationAttribution(datasets: rows.compactMap(\.dataset))
    }

    /// 有効な版から、取り込みも確認もしていない状態を作ります。
    ///
    /// 責務: 47県の行をそろえ、有効な版を県ごとに割り当てます。
    /// - Parameter datasets: 有効な版。
    /// - Returns: 初期状態。
    static func initial(datasets: [RoadRegulationDataset]) -> RoadRegulationSettingsState {
        var state = RoadRegulationSettingsState(
            rows: JapanesePrefectureCode.all.map { Self.row($0, dataset: nil, activeImport: nil, lastFailure: nil) },
            catalogStatus: .notChecked,
            importingPrefecture: nil,
            pendingRemoval: nil,
            presentedError: nil
        )
        state.replaceDatasets(datasets)
        return state
    }

    /// 指定した県の行を返します。
    ///
    /// 責務: 県コードから行を引きます。
    /// - Parameter prefecture: 県。
    /// - Returns: 行。
    func row(for prefecture: JapanesePrefectureCode) -> RoadRegulationPrefectureRow? {
        rows.first { $0.prefecture == prefecture }
    }

    /// 有効な版を読み直した結果で、行の版を置き換えます。
    ///
    /// 責務: 取り込み中の段階と失敗の記録を保ったまま、版だけを置き換えます。
    /// - Parameter datasets: 有効な版(同じ県が複数あれば後の方を使います)。
    mutating func replaceDatasets(_ datasets: [RoadRegulationDataset]) {
        let byPrefecture = Dictionary(datasets.map { ($0.prefecture, $0) }, uniquingKeysWith: { _, last in last })
        updateRows { row in (byPrefecture[row.prefecture], row.activeImport, row.lastFailure) }
    }

    /// 一覧の確認の状態を変えます。
    ///
    /// 責務: 確認の状態を置き換え、更新ありの印を付け直します。
    /// - Parameter status: 新しい確認の状態。
    mutating func setCatalogStatus(_ status: RoadRegulationCatalogCheckStatus) {
        catalogStatus = status
        updateRows { row in (row.dataset, row.activeImport, row.lastFailure) }
    }

    /// 県の取り込みを始めます。
    ///
    /// 責務: 取り込み中の県が無く、その行が取得できる時だけ、取り込み中にします。
    /// - Parameter prefecture: 取り込む県。
    /// - Returns: 始めたら `true`。
    mutating func beginImport(of prefecture: JapanesePrefectureCode) -> Bool {
        guard importingPrefecture == nil, row(for: prefecture)?.canStartDownload == true else { return false }
        importingPrefecture = prefecture
        updateRow(prefecture) { row in (row.dataset, .preparing, nil) }
        return true
    }

    /// 取り込み中の段階を更新します。
    ///
    /// 責務: 取り込み中の県の行に、新しい段階を記録します。
    /// - Parameter phase: 新しい段階。
    mutating func updateImport(_ phase: RoadRegulationImportPhase) {
        guard let prefecture = importingPrefecture else { return }
        updateRow(prefecture) { row in (row.dataset, phase, row.lastFailure) }
    }

    /// 取り込みの完了を反映します。
    ///
    /// 責務: 新しい版を行に入れ、取り込み中を終えます。
    /// - Parameter dataset: 有効にした版。
    mutating func completeImport(with dataset: RoadRegulationDataset) {
        importingPrefecture = nil
        updateRow(dataset.prefecture) { _ in (dataset, nil, nil) }
    }

    /// 取り込みの失敗を反映します。
    ///
    /// 責務: 手元の版を残したまま失敗を記録し、取り込み中を終えて、エラーを画面に出します。
    /// - Parameter error: 失敗の種類。
    mutating func failImport(_ error: RoadRegulationImportError) {
        guard let prefecture = importingPrefecture else { return }
        importingPrefecture = nil
        presentedError = error
        updateRow(prefecture) { row in (row.dataset, nil, error) }
    }

    /// 取り込みの中止を反映します。
    ///
    /// 責務: 取り込み中を終え、行を取り込み前の版の表示に戻します(エラーは出しません)。
    mutating func cancelImport() {
        guard let prefecture = importingPrefecture else { return }
        importingPrefecture = nil
        updateRow(prefecture) { row in (row.dataset, nil, row.lastFailure) }
    }

    /// 削除の確認を求めます。
    ///
    /// 責務: 取得済みで削除できる行の時だけ、確認を出す県にします。
    /// - Parameter prefecture: 削除する県。
    mutating func requestRemoval(of prefecture: JapanesePrefectureCode) {
        guard row(for: prefecture)?.canRemove == true else { return }
        pendingRemoval = prefecture
    }

    /// 削除の確認を受け、削除する県を返します。
    ///
    /// 責務: 確認を閉じ、取り込み中でなければ削除する県を返します。
    /// - Returns: 削除する県。確認が無いか取り込み中なら `nil`。
    mutating func confirmRemoval() -> JapanesePrefectureCode? {
        defer { pendingRemoval = nil }
        guard importingPrefecture == nil else { return nil }
        return pendingRemoval
    }

    /// 削除の完了を反映します。
    ///
    /// 責務: 行の版と失敗の記録を消し、未取得に戻します。
    /// - Parameter prefecture: 削除した県。
    mutating func completeRemoval(of prefecture: JapanesePrefectureCode) {
        updateRow(prefecture) { row in (nil, row.activeImport, nil) }
    }

    /// 1つの県の行を作り直します。
    ///
    /// 責務: 指定した県だけ、版・段階・失敗を置き換えます。
    /// - Parameters:
    ///   - prefecture: 県。
    ///   - change: 古い行から新しい版・段階・失敗を返す処理。
    private mutating func updateRow(_ prefecture: JapanesePrefectureCode, _ change: (RoadRegulationPrefectureRow) -> RowContent) {
        updateRows { row in row.prefecture == prefecture ? change(row) : (row.dataset, row.activeImport, row.lastFailure) }
    }

    /// すべての行を作り直し、更新ありとほかの県の取り込み中の印を付け直します。
    ///
    /// 責務: 行ごとの版・段階・失敗を受け取り、一覧と取り込み中の県から導く値をそろえます。
    /// - Parameter change: 古い行から新しい版・段階・失敗を返す処理。
    private mutating func updateRows(_ change: (RoadRegulationPrefectureRow) -> RowContent) {
        let catalog = catalogStatus.catalog
        let importing = importingPrefecture
        rows = rows.map { row in
            let content = change(row)
            var rebuilt = Self.row(row.prefecture, dataset: content.dataset, activeImport: content.activeImport, lastFailure: content.lastFailure,
                                   catalog: catalog)
            rebuilt.isBlockedByOtherImport = importing != nil && importing != row.prefecture
            return rebuilt
        }
    }

    /// 1行を作ります。
    ///
    /// 責務: 一覧の公開の印と手元の版を比べ、更新ありの印を決めます。
    /// - Parameters:
    ///   - prefecture: 県。
    ///   - dataset: 有効な版。
    ///   - activeImport: 取り込み中の段階。
    ///   - lastFailure: 最後の失敗。
    ///   - catalog: 確かめた一覧。
    /// - Returns: 行。
    private static func row(
        _ prefecture: JapanesePrefectureCode,
        dataset: RoadRegulationDataset?,
        activeImport: RoadRegulationImportPhase?,
        lastFailure: RoadRegulationImportError?,
        catalog: RoadRegulationCatalog? = nil
    ) -> RoadRegulationPrefectureRow {
        let catalogStamp = catalog?.entry(for: prefecture)?.publicationStamp
        let isUpdateAvailable = dataset.map { catalogStamp != nil && catalogStamp != $0.publicationStamp } ?? false
        return RoadRegulationPrefectureRow(
            prefecture: prefecture, dataset: dataset, activeImport: activeImport,
            lastFailure: lastFailure, isUpdateAvailable: isUpdateAvailable
        )
    }

    /// 行ごとに置き換える値(版・段階・失敗)。
    private typealias RowContent = (dataset: RoadRegulationDataset?, activeImport: RoadRegulationImportPhase?, lastFailure: RoadRegulationImportError?)
}

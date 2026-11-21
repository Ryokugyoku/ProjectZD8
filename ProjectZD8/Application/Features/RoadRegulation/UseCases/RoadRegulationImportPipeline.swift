import Foundation

/// 1県の交通規制データを取り込む手順を、メインスレッドの外で上から順に実行する型です(設計書 §3.7)。
///
/// 1. 残っている取り込み中・引退済みの版と ZIP を消す。
/// 2. 一覧を取る(渡された一覧があればそれを使う)。県が無ければ `prefectureNotInCatalog`。
/// 3. 空き容量 ≥ 100 MB を確かめてからダウンロードする。
/// 4. 空き容量 ≥ ZIP の大きさ × 3 + 50 MB を確かめる。
/// 5. 新しい版を始め、ZIP を読みながら一定件数ごとに書く(`RoadRegulationArchiveImportStep`)。
/// 6. 有効な版を入れ替え、古い版を掃除する。
/// 7. 成功・失敗・取り消しにかかわらず ZIP を消す。
///
/// どこで失敗・取り消しになっても、それまで有効だった版は残り、取り込み途中の版は消します(後始末の失敗は元のエラーを隠しません)。
nonisolated struct RoadRegulationImportPipeline: Sendable {
    /// ダウンロード前に必要な空き容量(100 MB。1 MB = 1,000,000 B)。
    static let minimumFreeBytesBeforeDownload: Int64 = 100_000_000
    /// ダウンロード後に、ZIP の大きさの3倍に足す空き容量(50 MB)。
    static let extraFreeBytesAfterDownload: Int64 = 50_000_000
    /// ダウンロード後に必要な空き容量の、ZIP の大きさに掛ける倍率。
    static let archiveSizeMultiplier: Int64 = 3

    /// 一覧と ZIP の取得元。
    let source: any RoadRegulationSourcePort
    /// 空き容量。
    let capacity: any RoadRegulationStorageCapacityPort
    /// 版の保存先。
    let datasets: any RoadRegulationDatasetRepository
    /// ZIP の読み取りから有効化までの手順。
    let archiveImport: RoadRegulationArchiveImportStep
    /// 失敗の分類。
    private let classifier = RoadRegulationImportErrorClassifier()

    /// 手順を最後まで実行し、結果を流れへ送ります。
    ///
    /// 責務: メインスレッドの外で手順を実行し、完了か分類した失敗で流れを閉じます。
    /// - Parameters:
    ///   - prefecture: 取り込む県。
    ///   - catalog: 確認済みの一覧。無ければ取得します。
    ///   - emitter: 事象の送り先。
    @concurrent
    func run(prefecture: JapanesePrefectureCode, catalog: RoadRegulationCatalog?, emitter: RoadRegulationImportEventEmitter) async {
        do {
            let dataset = try await perform(prefecture: prefecture, catalog: catalog, emitter: emitter)
            emitter.complete(with: dataset)
        } catch {
            emitter.fail(with: classifier.classified(error, fallback: .storageUnavailable))
        }
    }

    /// 手順を順に実行します。
    ///
    /// 責務: 準備・一覧・容量・ダウンロード・取り込みを呼び、ZIP を必ず消します。
    /// - Parameters:
    ///   - prefecture: 取り込む県。
    ///   - catalog: 確認済みの一覧。
    ///   - emitter: 事象の送り先。
    /// - Returns: 有効にした版。
    /// - Throws: 取り込みのエラーか `CancellationError`。
    private func perform(
        prefecture: JapanesePrefectureCode,
        catalog: RoadRegulationCatalog?,
        emitter: RoadRegulationImportEventEmitter
    ) async throws -> RoadRegulationDataset {
        emitter.report(.preparing)
        try purgeLeftovers()
        let resolved = try await resolveEntry(for: prefecture, catalog: catalog, emitter: emitter)
        try requireFreeBytes(Self.minimumFreeBytesBeforeDownload)
        let archiveURL = try await download(resolved.entry, emitter: emitter)
        defer { source.removeDownloadedArchive(at: archiveURL) }
        try Task.checkCancellation()
        try requireFreeBytes(Self.requiredFreeBytes(forArchiveBytes: archiveBytes(at: archiveURL, emitter: emitter)))
        let dataset = try archiveImport.importArchive(
            at: archiveURL,
            draft: RoadRegulationDatasetDraft(
                prefecture: prefecture, publicationStamp: resolved.entry.publicationStamp,
                sourceURL: resolved.entry.archiveURL, downloadedAt: archiveImport.now()
            ),
            catalogDataMonth: resolved.catalogDataMonth,
            emitter: emitter
        )
        emitter.report(.cleaningUp)
        try? datasets.purgeInactiveDatasets()
        return dataset
    }

    /// 以前の取り込みで残った版と ZIP を消します。
    ///
    /// 責務: 一時 ZIP と、取り込み中・引退済みの版を掃除します。
    /// - Throws: 版の掃除の失敗を分類したエラー。
    private func purgeLeftovers() throws {
        source.removeLeftoverDownloads()
        do {
            try datasets.purgeInactiveDatasets()
        } catch {
            throw classifier.classified(error, fallback: .storageUnavailable)
        }
    }

    /// 県の一覧の項目を決めます。
    ///
    /// 責務: 渡された一覧が無ければ取得し、県の項目と一覧の基準月を返します。
    /// - Parameters:
    ///   - prefecture: 取り込む県。
    ///   - catalog: 確認済みの一覧。
    ///   - emitter: 事象の送り先。
    /// - Returns: 県の項目と一覧の基準月。
    /// - Throws: 一覧の取得の失敗、県が無ければ `prefectureNotInCatalog`。
    private func resolveEntry(
        for prefecture: JapanesePrefectureCode,
        catalog: RoadRegulationCatalog?,
        emitter: RoadRegulationImportEventEmitter
    ) async throws -> (entry: RoadRegulationCatalogEntry, catalogDataMonth: RoadRegulationDataMonth?) {
        let resolvedCatalog: RoadRegulationCatalog
        if let catalog {
            resolvedCatalog = catalog
        } else {
            emitter.report(.fetchingCatalog)
            resolvedCatalog = try await fetchCatalog()
        }
        guard let entry = resolvedCatalog.entry(for: prefecture) else { throw RoadRegulationImportError.prefectureNotInCatalog }
        return (entry, resolvedCatalog.dataMonth)
    }

    /// 一覧を取得します。
    ///
    /// 責務: 取得元を呼び、想定外の失敗を `catalogUnavailable` にします。
    /// - Returns: 配布の一覧。
    /// - Throws: 分類した取得の失敗。
    private func fetchCatalog() async throws -> RoadRegulationCatalog {
        do {
            return try await source.currentCatalog()
        } catch {
            throw classifier.classified(error, fallback: .catalogUnavailable)
        }
    }

    /// ZIP をダウンロードします。
    ///
    /// 責務: ダウンロードの段階を知らせ、進捗を流しながら受け取ります。想定外の失敗は `downloadFailed` にします。
    /// - Parameters:
    ///   - entry: ダウンロードする項目。
    ///   - emitter: 事象の送り先。
    /// - Returns: 受け取った ZIP の場所。
    /// - Throws: 分類したダウンロードの失敗。
    private func download(_ entry: RoadRegulationCatalogEntry, emitter: RoadRegulationImportEventEmitter) async throws -> URL {
        emitter.report(.downloading(RoadRegulationTransferProgress(receivedBytes: 0, expectedBytes: nil)))
        do {
            return try await source.downloadArchive(for: entry) { emitter.reportDownload($0) }
        } catch {
            throw classifier.classified(error, fallback: .downloadFailed)
        }
    }

    /// 空き容量が足りるかを確かめます。
    ///
    /// 責務: 空き容量を読み、必要な量と比べます。
    /// - Parameter requiredBytes: 必要な空き容量。
    /// - Throws: 足りなければ `insufficientStorage`、空き容量を読めなければ `storageUnavailable`。
    private func requireFreeBytes(_ requiredBytes: Int64) throws {
        let available: Int64
        do {
            available = try capacity.availableCapacityBytes()
        } catch {
            throw classifier.classified(error, fallback: .storageUnavailable)
        }
        guard available >= requiredBytes else { throw RoadRegulationImportError.insufficientStorage }
    }

    /// 受け取った ZIP の大きさを求めます。
    ///
    /// 責務: ファイルの大きさを読み、読めなければダウンロードで受け取ったバイト数の最大を使います。
    /// - Parameters:
    ///   - url: 受け取った ZIP。
    ///   - emitter: 受け取ったバイト数を覚えている送り先。
    /// - Returns: ZIP の大きさ(バイト)。
    private func archiveBytes(at url: URL, emitter: RoadRegulationImportEventEmitter) -> Int64 {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return emitter.largestReceivedBytes }
        return Int64(size)
    }

    /// ダウンロード後に必要な空き容量を求めます。
    ///
    /// 責務: 「ZIP の大きさ × 3 + 50 MB」を、桁あふれしないように計算します。
    /// - Parameter archiveBytes: ZIP の大きさ。
    /// - Returns: 必要な空き容量(あふれる時は `Int64.max`)。
    static func requiredFreeBytes(forArchiveBytes archiveBytes: Int64) -> Int64 {
        let (scaled, scaleOverflow) = max(0, archiveBytes).multipliedReportingOverflow(by: archiveSizeMultiplier)
        let (total, addOverflow) = scaled.addingReportingOverflow(extraFreeBytesAfterDownload)
        return scaleOverflow || addOverflow ? Int64.max : total
    }
}

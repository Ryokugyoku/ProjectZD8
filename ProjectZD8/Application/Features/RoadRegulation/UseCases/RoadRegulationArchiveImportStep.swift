import Foundation

/// 受け取った ZIP を新しい版として取り込み、有効にするまでの手順です(設計書 §3.7 の 7〜10、13)。
///
/// 1. `beginImport` で取り込み中の版を始める。
/// 2. ZIP を読みながら `RoadRegulationImportBatchWriter` が一定件数ごとに書く。
/// 3. 取り込めた件数が0なら `noRegulationsInArchive`。基準月は CSV の名前から、無ければ一覧から取り、どちらも無ければ `csvFormatChanged`。
/// 4. 取り消しを確かめてから `activate` する。
///
/// 2〜4 のどこで失敗・取り消しになっても、取り込み中の版を `discard` してから元のエラーを投げます(`discard` の失敗は元のエラーを隠しません)。
nonisolated struct RoadRegulationArchiveImportStep: Sendable {
    /// ZIP の読み取り。
    let archiveReader: any RoadRegulationArchiveReaderPort
    /// 版の保存先。
    let datasets: any RoadRegulationDatasetRepository
    /// 升目の計算。
    let grid: RoadRegulationGrid
    /// 1回に書く件数。
    let batchSize: Int
    /// 現在時刻。
    let now: @Sendable () -> Date
    /// 失敗の分類。
    private let classifier = RoadRegulationImportErrorClassifier()

    /// 手順に使う部品を受け取ります。
    ///
    /// 責務: 読み取り・保存・升目・書き込みの単位・時刻を保持します。
    /// - Parameters:
    ///   - archiveReader: ZIP の読み取り。
    ///   - datasets: 版の保存先。
    ///   - grid: 升目の計算。
    ///   - batchSize: 1回に書く件数。
    ///   - now: 現在時刻。
    init(
        archiveReader: any RoadRegulationArchiveReaderPort,
        datasets: any RoadRegulationDatasetRepository,
        grid: RoadRegulationGrid,
        batchSize: Int,
        now: @escaping @Sendable () -> Date
    ) {
        self.archiveReader = archiveReader
        self.datasets = datasets
        self.grid = grid
        self.batchSize = batchSize
        self.now = now
    }

    /// ZIP を新しい版として取り込み、有効にします。
    ///
    /// 責務: 版を始め、読み取りと書き込みを行い、有効にします。失敗した時は取り込み中の版を捨てます。
    /// - Parameters:
    ///   - url: 受け取った ZIP。
    ///   - draft: 新しい版の情報。
    ///   - catalogDataMonth: 一覧の基準月(CSV の名前から取れない時に使います)。
    ///   - emitter: 事象の送り先。
    /// - Returns: 有効にした版。
    /// - Throws: 取り込みのエラーか `CancellationError`。
    func importArchive(
        at url: URL,
        draft: RoadRegulationDatasetDraft,
        catalogDataMonth: RoadRegulationDataMonth?,
        emitter: RoadRegulationImportEventEmitter
    ) throws -> RoadRegulationDataset {
        let datasetID = try classifying { try datasets.beginImport(draft) }
        do {
            let summary = try readArchive(at: url, into: datasetID, catalogDataMonth: catalogDataMonth, emitter: emitter)
            try Task.checkCancellation()
            emitter.report(.activating)
            return try classifying { try datasets.activate(datasetID, summary: summary, activatedAt: now()) }
        } catch {
            try? datasets.discard(datasetID)
            throw error
        }
    }

    /// ZIP を読み、取り込み中の版へ書き、版のまとめを作ります。
    ///
    /// 責務: 読み取りの進捗を流しながら、記録を書き込みへ渡し、最後に残りを書きます。
    /// - Parameters:
    ///   - url: 受け取った ZIP。
    ///   - datasetID: 取り込み中の版。
    ///   - catalogDataMonth: 一覧の基準月。
    ///   - emitter: 事象の送り先。
    /// - Returns: 有効化に使う版のまとめ。
    /// - Throws: 読み取り・書き込みの失敗、件数0、基準月が無い時の失敗。
    private func readArchive(
        at url: URL,
        into datasetID: RoadRegulationDatasetID,
        catalogDataMonth: RoadRegulationDataMonth?,
        emitter: RoadRegulationImportEventEmitter
    ) throws -> RoadRegulationImportSummary {
        emitter.report(.importing(RoadRegulationArchiveReadProgress(processedCompressedBytes: 0, totalCompressedBytes: 0), importedCount: 0))
        var writer = RoadRegulationImportBatchWriter(datasetID: datasetID, repository: datasets, grid: grid, batchSize: batchSize)
        var importedCount = 0
        let archive = try classifying {
            try archiveReader.read(
                archiveAt: url,
                progress: { emitter.report(.importing($0, importedCount: importedCount)) },
                consume: { record in
                    try writer.accept(record)
                    importedCount = writer.importedCount
                }
            )
        }
        let written = try classifying { try writer.finish(totalRows: archive.totalRows) }
        return try Self.summary(of: archive, counts: written.counts, coverage: written.coverage, catalogDataMonth: catalogDataMonth)
    }

    /// 版のまとめを作ります。
    ///
    /// 責務: 件数0と基準月の欠落を失敗にし、有効化に使う値をそろえます。
    /// - Parameters:
    ///   - archive: 読み終えた時の情報。
    ///   - counts: 取り込みの件数。
    ///   - coverage: 版の範囲。
    ///   - catalogDataMonth: 一覧の基準月。
    /// - Returns: 版のまとめ。
    /// - Throws: 件数0(または範囲が無い)なら `noRegulationsInArchive`、基準月が無ければ `csvFormatChanged`。
    static func summary(
        of archive: RoadRegulationArchiveSummary,
        counts: RoadRegulationImportCounts,
        coverage: GeoBoundingBox?,
        catalogDataMonth: RoadRegulationDataMonth?
    ) throws -> RoadRegulationImportSummary {
        guard counts.importedRegulations > 0, let coverage else { throw RoadRegulationImportError.noRegulationsInArchive }
        guard let dataMonth = archive.dataMonth ?? catalogDataMonth else { throw RoadRegulationImportError.csvFormatChanged }
        return RoadRegulationImportSummary(dataMonth: dataMonth, formatVersion: archive.formatVersion, counts: counts, coverage: coverage)
    }

    /// 処理の失敗を取り込みのエラーに分類して投げ直します。
    ///
    /// 責務: リポジトリの失敗を `insufficientStorage` / `storageUnavailable` に直し、取り消しはそのまま投げます。
    /// - Parameter body: 実行する処理。
    /// - Returns: 処理の結果。
    /// - Throws: 分類したエラー。
    private func classifying<Value>(_ body: () throws -> Value) throws -> Value {
        do {
            return try body()
        } catch {
            throw classifier.classified(error, fallback: .storageUnavailable)
        }
    }
}

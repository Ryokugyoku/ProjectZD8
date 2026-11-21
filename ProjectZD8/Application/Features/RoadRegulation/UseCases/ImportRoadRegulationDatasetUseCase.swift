import Foundation

/// 1県の交通規制データを取得して新しい版として取り込み、進捗と完了を事象の流れで伝えるユースケースです。
///
/// 手順は `RoadRegulationImportPipeline`(設計書 §3.7)が、メインスレッドの外の Task で実行します。
/// - 事象は「準備 → (一覧) → ダウンロード → 取り込み → 有効化 → 掃除 → 完了」の順で、進捗は間引いて流します。
///   一覧の段階は、一覧を渡さなかった時だけ流します。
/// - 失敗は `RoadRegulationImportError`、取り消しは `CancellationError` で流れを終えます。
/// - 消費側が流れを取り消すと(`onTermination`)、作り手の Task を取り消します。後始末は作り手が必ず行います。
nonisolated struct ImportRoadRegulationDatasetUseCase: Sendable {
    /// 取り込みの手順。
    private let pipeline: RoadRegulationImportPipeline

    /// 取り込みに使う部品を受け取ります。
    ///
    /// 責務: 取得元・読み取り・保存先・空き容量・升目・書き込みの単位・時刻から、取り込みの手順を組み立てます。
    /// - Parameters:
    ///   - source: 一覧と ZIP の取得元。
    ///   - archiveReader: ZIP の読み取り。
    ///   - datasets: 版の保存先。
    ///   - capacity: 空き容量。
    ///   - grid: 升目の計算。
    ///   - batchSize: 1回に書く件数。既定 1,000。
    ///   - now: 現在時刻。
    init(
        source: any RoadRegulationSourcePort,
        archiveReader: any RoadRegulationArchiveReaderPort,
        datasets: any RoadRegulationDatasetRepository,
        capacity: any RoadRegulationStorageCapacityPort,
        grid: RoadRegulationGrid = .init(),
        batchSize: Int = 1_000,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        pipeline = RoadRegulationImportPipeline(
            source: source,
            capacity: capacity,
            datasets: datasets,
            archiveImport: RoadRegulationArchiveImportStep(
                archiveReader: archiveReader, datasets: datasets, grid: grid, batchSize: batchSize, now: now
            )
        )
    }

    /// 取り込みを始め、その事象の流れを返します。
    ///
    /// 責務: 作り手の Task を起動し、消費側の取り消しを Task の取り消しへつなぎます。
    /// - Parameters:
    ///   - prefecture: 取り込む県。
    ///   - catalog: 確認済みの一覧。`nil` なら取り込みの中で取得します。
    /// - Returns: 進捗と完了の事象の流れ。
    func events(
        for prefecture: JapanesePrefectureCode,
        catalog: RoadRegulationCatalog?
    ) -> AsyncThrowingStream<RoadRegulationImportEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: RoadRegulationImportEvent.self, throwing: (any Error).self)
        let emitter = RoadRegulationImportEventEmitter(continuation: continuation)
        let pipeline = pipeline
        let task = Task {
            await pipeline.run(prefecture: prefecture, catalog: catalog, emitter: emitter)
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}

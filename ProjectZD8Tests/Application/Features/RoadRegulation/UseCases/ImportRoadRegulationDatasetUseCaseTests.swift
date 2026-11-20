import Foundation
import XCTest
@testable import ProjectZD8

/// `ImportRoadRegulationDatasetUseCase` の正常な流れ(段階の順序・通知の順・版の値・要約・進捗の間引き)を検証します。
///
/// 失敗と取り消しは `ImportRoadRegulationDatasetUseCaseFailureTests` / `...CancellationTests`、空き容量は `...CapacityTests` で検証します。
@MainActor
final class ImportRoadRegulationDatasetUseCaseTests: XCTestCase {
    private typealias Values = RoadRegulationTestValues
    private var harness: RoadRegulationImportHarness!

    override func setUp() async throws {
        try await super.setUp()
        harness = try RoadRegulationImportHarness()
    }

    override func tearDown() async throws {
        harness.tearDown()
        harness = nil
        try await super.tearDown()
    }

    /// 責務: 通知を段階の名前に直し、続けて同じ名前を1つにまとめます。
    static func collapsedPhaseNames(_ events: [RoadRegulationImportEvent]) -> [String] {
        let names = events.map(phaseName)
        return names.enumerated().filter { $0.offset == 0 || names[$0.offset - 1] != $0.element }.map(\.element)
    }

    /// 責務: 通知1件を段階の名前に直します。
    static func phaseName(_ event: RoadRegulationImportEvent) -> String {
        switch event {
        case .completed: "completed"
        case .progress(.preparing): "preparing"
        case .progress(.fetchingCatalog): "fetchingCatalog"
        case .progress(.downloading): "downloading"
        case .progress(.importing): "importing"
        case .progress(.activating): "activating"
        case .progress(.cleaningUp): "cleaningUp"
        }
    }

    /// 責務: 帳面の位置を取り出し、無ければ失敗させます。
    private func index(_ value: Int?, _ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Int {
        try XCTUnwrap(value, "\(name) が呼ばれていません", file: file, line: line)
    }

    /// 一覧を渡さない正常な流れで、通知が「準備 → 一覧 → ダウンロード → 取り込み → 有効化 → 掃除 → 完了」の順に来ます。
    ///
    /// 責務: 段階の順と、最後の通知が完了であることを確認します。
    func testNotifiesPhasesInOrder() async throws {
        let outcome = try await harness.runOrFail(on: self)

        XCTAssertNil(outcome.failure)
        XCTAssertEqual(Self.collapsedPhaseNames(outcome.events), [
            "preparing", "fetchingCatalog", "downloading", "importing", "activating", "cleaningUp", "completed",
        ])
    }

    /// 各段階が、空き容量 → ダウンロード → 空き容量 → 版の開始 → 読み取り → 書き込み → 有効化 → 掃除 の順に呼ばれます。
    ///
    /// 責務: 偽物どうしで共有した帳面の位置で、段階の前後関係を確認します。
    func testCallsStagesInOrder() async throws {
        _ = try await harness.runOrFail(on: self)
        let log = harness.log

        let leftovers = try index(log.firstIndex(of: .removeLeftoverDownloads), "残ったダウンロードの掃除")
        let catalog = try index(log.firstIndex(of: .fetchCatalog), "一覧の取得")
        let firstCapacity = try index(log.firstIndex(of: .availableCapacity), "ダウンロード前の空き容量")
        let download = try index(log.firstIndex(of: .download), "ダウンロード")
        let lastCapacity = try index(log.lastIndex(of: .availableCapacity), "ダウンロード後の空き容量")
        let begin = try index(log.firstIndex(of: .beginImport), "版の開始")
        let read = try index(log.firstIndex(of: .read), "読み取り")
        let append = try index(log.firstAppendIndex(), "書き込み")
        let activate = try index(log.firstIndex(of: .activate), "有効化")
        let purge = try index(log.lastIndex(of: .purgeInactiveDatasets), "古い版の掃除")
        let firstPurge = try index(log.firstIndex(of: .purgeInactiveDatasets), "残った版の掃除")
        let removeFile = try index(log.lastIndex(of: .removeDownloadedArchive), "ZIP の削除")

        XCTAssertLessThan(leftovers, download)
        XCTAssertLessThan(firstPurge, begin)
        XCTAssertLessThan(catalog, download)
        XCTAssertLessThan(firstCapacity, download)
        XCTAssertLessThan(download, lastCapacity)
        XCTAssertLessThan(lastCapacity, begin)
        XCTAssertLessThan(begin, read)
        XCTAssertLessThan(read, append)
        XCTAssertLessThan(append, activate)
        XCTAssertLessThan(activate, purge)
        XCTAssertLessThan(read, removeFile)
        XCTAssertEqual(harness.capacity.returnedValues.count, 2)
    }

    /// 成功すると新しい版が有効になり、古い版は掃除され、完了の通知が有効化した版を運び、ZIP が消えます。
    ///
    /// 責務: 有効な版の入れ替わり・完了の値・一時ファイルの削除を確認します。
    func testSuccessActivatesNewDatasetAndRemovesArchive() async throws {
        let previous = harness.seedPreviousActive()

        let outcome = try await harness.runOrFail(on: self)

        let activated = try XCTUnwrap(harness.datasets.currentActiveDatasets.first)
        XCTAssertEqual(harness.datasets.currentActiveDatasets.count, 1)
        XCTAssertNotEqual(activated.id, previous.id)
        XCTAssertEqual(outcome.events.last, .completed(activated))
        XCTAssertTrue(harness.datasets.retiredDatasetIDs.isEmpty, "古い版が掃除されていません")
        XCTAssertTrue(harness.datasets.importingDatasetIDs.isEmpty)
        XCTAssertEqual(harness.source.createdURLs.count, 1)
        XCTAssertTrue(harness.source.remainingFiles.isEmpty)
        XCTAssertEqual(harness.reader.readURLs, harness.source.createdURLs)
    }

    /// 有効化が済んだ後の掃除が失敗しても、取り込みは完了になり、新しい版が有効なままです。
    ///
    /// 責務: 有効化の後の掃除の失敗を無視することを確認します。
    func testCleanupFailureAfterActivationStillCompletes() async throws {
        harness.seedPreviousActive()
        harness.datasets.failPurgeAfterActivation(with: .unavailable)

        let outcome = try await harness.runOrFail(on: self)

        let activated = try XCTUnwrap(harness.datasets.currentActiveDatasets.first)
        XCTAssertNil(outcome.failure)
        XCTAssertEqual(outcome.events.last, .completed(activated))
        XCTAssertEqual(harness.datasets.activations.map(\.datasetID), [activated.id])
        XCTAssertTrue(harness.source.remainingFiles.isEmpty)
    }

    /// 版の開始には、一覧の行の公開の印と URL、取得の時刻が入ります。
    ///
    /// 責務: `beginImport` に渡す下書きの値を確認します。
    func testBeginImportUsesCatalogEntryAndNow() async throws {
        let entry = Values.catalogEntry(RoadRegulationImportHarness.prefecture, stamp: "202612010000")
        let catalog = RoadRegulationCatalog(dataMonth: Values.month(2026, 10), entries: [entry])

        _ = try await harness.runOrFail(catalog: catalog, on: self)

        XCTAssertEqual(harness.datasets.begunDrafts, [RoadRegulationDatasetDraft(
            prefecture: RoadRegulationImportHarness.prefecture, publicationStamp: "202612010000",
            sourceURL: entry.archiveURL, downloadedAt: Values.fixedNow
        )])
        XCTAssertEqual(harness.source.downloadedEntries, [entry])
    }

    /// 一覧を渡すと、一覧を取りに行かずにそれを使います。
    ///
    /// 責務: 渡された一覧が使われ、`currentCatalog` が呼ばれないことを確認します。
    func testProvidedCatalogIsUsedWithoutFetching() async throws {
        let outcome = try await harness.runOrFail(catalog: Values.catalog([RoadRegulationImportHarness.prefecture]), on: self)

        XCTAssertNil(outcome.failure)
        XCTAssertEqual(harness.source.catalogCallCount, 0)
        XCTAssertEqual(Self.collapsedPhaseNames(outcome.events), [
            "preparing", "downloading", "importing", "activating", "cleaningUp", "completed",
        ])
    }

    /// 有効化の要約は、読み取りの基準月と版、書き込みの件数、全規制の外接矩形の和です。時刻は固定の `now` です。
    ///
    /// 責務: `activate` に渡す要約と時刻を、台本と形状から手で求めた値と照らします。
    func testActivationSummaryCombinesReaderAndWriterResults() async throws {
        _ = try await harness.runOrFail(on: self)

        let activation = try XCTUnwrap(harness.datasets.activations.first)
        let points = RoadRegulationImportHarness.defaultRegulations.flatMap { $0.geometry.mainParts.flatMap { $0 } + $0.geometry.approachPoints }
        XCTAssertEqual(activation.activatedAt, Values.fixedNow)
        XCTAssertEqual(activation.summary.dataMonth, Values.month(2026, 9))
        XCTAssertEqual(activation.summary.formatVersion, "k_2.1")
        XCTAssertEqual(activation.summary.counts.totalRows, 3)
        XCTAssertEqual(activation.summary.counts.importedRegulations, 2)
        XCTAssertEqual(activation.summary.counts.skippedOutOfScope, 1)
        XCTAssertEqual(activation.summary.counts.rejectedRows, 0)
        XCTAssertEqual(activation.summary.coverage, Values.box(
            minLatitude: points.map(\.latitude).min() ?? 0, maxLatitude: points.map(\.latitude).max() ?? 0,
            minLongitude: points.map(\.longitude).min() ?? 0, maxLongitude: points.map(\.longitude).max() ?? 0
        ))
    }

    /// 読み取りの基準月が無い時は、一覧の基準月を使います。
    ///
    /// 責務: CSV の名前から基準月が取れない時の補い方を確認します。
    func testFallsBackToCatalogMonthWhenArchiveHasNone() async throws {
        var script = RoadRegulationImportHarness.defaultScript()
        script.summary = RoadRegulationArchiveSummary(dataMonth: nil, formatVersion: "k_2.1", totalRows: 3)
        harness.reader.replaceScript(script)
        let catalog = Values.catalog([RoadRegulationImportHarness.prefecture], dataMonth: Values.month(2026, 7))

        let outcome = try await harness.runOrFail(catalog: catalog, on: self)

        XCTAssertNil(outcome.failure)
        XCTAssertEqual(harness.datasets.activations.first?.summary.dataMonth, Values.month(2026, 7))
    }

    /// 書き込みは件数(batchSize)ごとにまとまります(batchSize = 2 で5件なら 2・2・1 の3回)。
    ///
    /// 責務: 取り込みのユースケースが batchSize を書き込みへ渡していることを確認します。
    func testWritesInBatchesOfBatchSize() async throws {
        var script = RoadRegulationImportHarness.defaultScript()
        script.records = (0..<5).map { .regulation(Values.eastwardLineDraft("K\($0)")) }
        harness.reader.replaceScript(script)

        let outcome = try await harness.runOrFail(batchSize: 2, on: self)

        XCTAssertNil(outcome.failure)
        XCTAssertEqual(harness.datasets.appendedBatches.map(\.count).filter { $0 > 0 }, [2, 2, 1])
    }

    /// 同じ値の進捗が何度届いても、続けて同じ通知は出しません。取り込みの進捗の値は減りません。
    ///
    /// 責務: 重複した進捗が抑えられ、取り込みの通知が単調であることを確認します。
    func testSuppressesRepeatedProgressValues() async throws {
        var script = RoadRegulationImportHarness.defaultScript()
        let same = RoadRegulationArchiveReadProgress(processedCompressedBytes: 300, totalCompressedBytes: 1_000)
        script.progressSteps = Array(repeating: same, count: 50) + script.progressSteps
        harness.reader.replaceScript(script)

        let outcome = try await harness.runOrFail(on: self)

        let events = outcome.events
        XCTAssertFalse(zip(events, events.dropFirst()).contains { $0 == $1 }, "同じ通知が続きました: \(events)")
        let processed = events.compactMap { event -> Int64? in
            guard case .progress(.importing(let progress, _)) = event else { return nil }
            return progress.processedCompressedBytes
        }
        XCTAssertEqual(processed, processed.sorted())
    }

    /// 同じ段階で頻繁に(0.01% ずつ1万回)進捗が届いても、通知は間引かれます。
    ///
    /// 責務: 取り込みの通知の数が、1% 刻みで出る数(約100)を大きく超えないことを確認します。
    func testThrottlesFrequentProgressWithinPhase() async throws {
        var script = RoadRegulationImportHarness.defaultScript()
        script.progressSteps = (1...10_000).map {
            RoadRegulationArchiveReadProgress(processedCompressedBytes: Int64($0) * 10, totalCompressedBytes: 100_000)
        }
        harness.reader.replaceScript(script)

        let outcome = try await harness.runOrFail(on: self)

        let importing = outcome.events.filter { Self.phaseName($0) == "importing" }
        XCTAssertGreaterThanOrEqual(importing.count, 2)
        XCTAssertLessThanOrEqual(importing.count, 110, "通知が間引かれていません: \(importing.count) 件")
        XCTAssertEqual(outcome.events.last.map(Self.phaseName), "completed")
    }
}

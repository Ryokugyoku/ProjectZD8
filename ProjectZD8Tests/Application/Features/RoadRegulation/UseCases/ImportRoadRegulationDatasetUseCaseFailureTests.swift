import Foundation
import XCTest
@testable import ProjectZD8

/// `ImportRoadRegulationDatasetUseCase` が、どの段階で失敗しても、有効な版を変えず、取り込み途中の版とダウンロードしたファイルを
/// 残さず、エラーを正しく分類して伝えることを、段階ごとに失敗を注入して検証します。
@MainActor
final class ImportRoadRegulationDatasetUseCaseFailureTests: XCTestCase {
    private typealias Values = RoadRegulationTestValues
    private var harness: RoadRegulationImportHarness!
    private var previous: [RoadRegulationDataset] = []

    override func setUp() async throws {
        try await super.setUp()
        harness = try RoadRegulationImportHarness()
        previous = [harness.seedPreviousActive()]
    }

    override func tearDown() async throws {
        harness.tearDown()
        harness = nil
        try await super.tearDown()
    }

    /// 責務: 取り込みを走らせ、指定のエラーで失敗し、何も残していないことを確かめます。
    private func assertFails(
        with expected: RoadRegulationImportError,
        catalog: RoadRegulationCatalog? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let outcome = try await harness.runOrFail(catalog: catalog, on: self, file: file, line: line)
        XCTAssertEqual(outcome.failure, .importError(expected), file: file, line: line)
        XCTAssertFalse(outcome.events.contains { if case .completed = $0 { true } else { false } }, file: file, line: line)
        harness.assertNothingLeftBehind(previouslyActive: previous, file: file, line: line)
    }

    /// 一覧の取得が通信で失敗すると `catalogUnavailable` で、ダウンロードしません。
    ///
    /// 責務: 一覧の段階の失敗(通信)を確認します。
    func testCatalogUnavailableStopsBeforeDownload() async throws {
        harness.source.failCatalog(with: .catalogUnavailable)

        try await assertFails(with: .catalogUnavailable)
        XCTAssertTrue(harness.source.downloadedEntries.isEmpty)
    }

    /// 一覧の形式が変わっていると `catalogFormatChanged` で、手元の版を使い続けます。
    ///
    /// 責務: 一覧の段階の失敗(形式の変化)を確認します。
    func testCatalogFormatChangeKeepsLocalData() async throws {
        harness.source.failCatalog(with: .catalogFormatChanged)

        try await assertFails(with: .catalogFormatChanged)
        XCTAssertTrue(harness.datasets.begunIDs.isEmpty)
    }

    /// 一覧に県が無いと `prefectureNotInCatalog` で、ダウンロードしません。
    ///
    /// 責務: 県の行が無い一覧での失敗を確認します。
    func testPrefectureMissingFromCatalog() async throws {
        try await assertFails(with: .prefectureNotInCatalog, catalog: Values.catalog([Values.prefecture(13)]))
        XCTAssertTrue(harness.source.downloadedEntries.isEmpty)
    }

    /// ダウンロードが失敗すると `downloadFailed` で、版を始めません。
    ///
    /// 責務: ダウンロードの段階の失敗を確認します。
    func testDownloadFailureStopsBeforeBeginImport() async throws {
        harness.source.failDownload(with: .downloadFailed)

        try await assertFails(with: .downloadFailed)
        XCTAssertTrue(harness.datasets.begunIDs.isEmpty)
    }

    /// 空き容量を読めない時は `storageUnavailable` で、ダウンロードしません。
    ///
    /// 責務: 空き容量の読み取りの失敗の分類を確認します。
    func testCapacityReadFailureIsStorageUnavailable() async throws {
        harness.capacity.fail(with: .unavailable)

        try await assertFails(with: .storageUnavailable)
        XCTAssertTrue(harness.source.downloadedEntries.isEmpty)
    }

    /// 版の開始が保存の失敗(DB が使えない)なら `storageUnavailable` です。
    ///
    /// 責務: 版の開始の段階の失敗と、保存のエラーの分類を確認します。
    func testBeginImportUnavailableIsStorageUnavailable() async throws {
        harness.datasets.fail(.beginImport, with: .unavailable)

        try await assertFails(with: .storageUnavailable)
        XCTAssertTrue(harness.reader.readURLs.isEmpty)
    }

    /// 書き込みが SQLITE_FULL(`storageFull`)で失敗すると `insufficientStorage` で、有効化しません。
    ///
    /// 責務: 書き込みの段階の失敗(容量)と分類を確認します。
    func testAppendStorageFullIsInsufficientStorage() async throws {
        harness.datasets.fail(.appendRegulations, with: .storageFull)

        try await assertFails(with: .insufficientStorage)
        XCTAssertTrue(harness.datasets.activations.isEmpty)
    }

    /// 2回目の書き込みが DB の失敗(`unavailable`)なら `storageUnavailable` で、1回目に書いた分も残りません。
    ///
    /// 責務: 途中まで書いた版が破棄されることを確認します。
    func testSecondAppendFailureDiscardsPartialDataset() async throws {
        var script = RoadRegulationImportHarness.defaultScript()
        script.records = (0..<5).map { .regulation(Values.eastwardLineDraft("K\($0)")) }
        harness.reader.replaceScript(script)
        harness.datasets.failAppend(onCallNumber: 2, with: .unavailable)

        let outcome = try await harness.runOrFail(batchSize: 2, on: self)

        XCTAssertEqual(outcome.failure, .importError(.storageUnavailable))
        XCTAssertTrue(harness.datasets.activations.isEmpty)
        harness.assertNothingLeftBehind(previouslyActive: previous)
    }

    /// 読み取りが ZIP の形式の失敗なら `archiveInvalid` のまま伝わり、有効化しません。
    ///
    /// 責務: 読み取りの段階の失敗(形式不正)を確認します。
    func testArchiveInvalidFromReaderPropagates() async throws {
        var script = RoadRegulationImportHarness.defaultScript()
        script.failure = .archiveInvalid
        harness.reader.replaceScript(script)

        try await assertFails(with: .archiveInvalid)
        XCTAssertTrue(harness.datasets.activations.isEmpty)
    }

    /// 読み取りが CSV の形式の失敗なら `csvFormatChanged` のまま伝わります。
    ///
    /// 責務: 読み取りの段階の失敗(列・版の変化)を確認します。
    func testCSVFormatChangeFromReaderPropagates() async throws {
        var script = RoadRegulationImportHarness.defaultScript()
        script.records = []
        script.failure = .csvFormatChanged
        harness.reader.replaceScript(script)

        try await assertFails(with: .csvFormatChanged)
    }

    /// 取り込めた件数が0なら `noRegulationsInArchive` で、有効化しません。
    ///
    /// 責務: 読み飛ばし・破棄だけのアーカイブを有効にしないことを確認します。
    func testZeroImportedRegulationsIsNotActivated() async throws {
        var script = RoadRegulationImportHarness.defaultScript()
        script.records = [.skipped(.outOfScopeKind), .rejected(.invalidSpeed)]
        harness.reader.replaceScript(script)

        try await assertFails(with: .noRegulationsInArchive)
        XCTAssertTrue(harness.datasets.activations.isEmpty)
    }

    /// 基準月が読み取りにも一覧にも無ければ `csvFormatChanged` です。
    ///
    /// 責務: 基準月を決められない時に有効化しないことを確認します。
    func testMissingDataMonthEverywhereIsFormatChange() async throws {
        var script = RoadRegulationImportHarness.defaultScript()
        script.summary = RoadRegulationArchiveSummary(dataMonth: nil, formatVersion: "k_2.1", totalRows: 3)
        harness.reader.replaceScript(script)

        try await assertFails(with: .csvFormatChanged, catalog: Values.catalog([RoadRegulationImportHarness.prefecture], dataMonth: nil))
        XCTAssertTrue(harness.datasets.activations.isEmpty)
    }

    /// 有効化が保存の失敗なら `storageUnavailable` で、古い版のままです。
    ///
    /// 責務: 有効化の段階の失敗を確認します。
    func testActivationFailureKeepsPreviousDataset() async throws {
        harness.datasets.fail(.activate, with: .unavailable)

        try await assertFails(with: .storageUnavailable)
        XCTAssertEqual(harness.datasets.activations.count, 1)
    }

    /// 後始末(破棄)が失敗しても、元のエラー(`archiveInvalid`)が報告されます。
    ///
    /// 責務: 後始末の失敗で元のエラーが置き換わらず、ZIP は消えることを確認します。
    func testCleanupFailureStillReportsOriginalError() async throws {
        var script = RoadRegulationImportHarness.defaultScript()
        script.failure = .archiveInvalid
        harness.reader.replaceScript(script)
        harness.datasets.fail(.discard, with: .unavailable)

        let outcome = try await harness.runOrFail(on: self)

        XCTAssertEqual(outcome.failure, .importError(.archiveInvalid))
        XCTAssertFalse(harness.datasets.discardedIDs.isEmpty, "破棄を試みていません")
        XCTAssertTrue(harness.source.remainingFiles.isEmpty)
        XCTAssertEqual(harness.datasets.currentActiveDatasets, previous)
    }
}

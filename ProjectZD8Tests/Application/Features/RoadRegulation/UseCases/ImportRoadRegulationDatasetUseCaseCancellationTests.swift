import Foundation
import XCTest
@testable import ProjectZD8

/// `ImportRoadRegulationDatasetUseCase` の通知の列を消費側が取り消すと、作り手の処理も止まり、有効な版を変えず、
/// 取り込み途中の版とダウンロードしたファイルを残さないことを、段階ごとに偽物を止めて検証します。
@MainActor
final class ImportRoadRegulationDatasetUseCaseCancellationTests: XCTestCase {
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

    /// 責務: 消費を始めます(取り消せる形で返します)。
    private func startConsuming(batchSize: Int = 1_000) -> TestBoundedAsyncRun<RoadRegulationImportHarness.Outcome> {
        let stream = harness.makeUseCase(batchSize: batchSize).events(for: RoadRegulationImportHarness.prefecture, catalog: nil)
        return TestBoundedAsyncRun { await RoadRegulationImportHarness.collect(stream) }
    }

    /// 責務: 取り消した消費が期限内に終わり、完了の通知を受け取っていないことを確かめます。
    private func assertEndedWithoutCompletion(
        _ run: TestBoundedAsyncRun<RoadRegulationImportHarness.Outcome>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        guard let outcome = await run.value(on: self, file: file, line: line) else { return }
        XCTAssertFalse(outcome.events.contains { if case .completed = $0 { true } else { false } }, file: file, line: line)
    }

    /// 一覧の取得中に取り消すと、ダウンロードも版の開始もしません。
    ///
    /// 責務: 一覧の段階の取り消しを確認します。
    func testCancellationWhileFetchingCatalogStopsEverything() async throws {
        harness.source.catalogGate.close()
        let run = startConsuming()
        guard await harness.waitUntil("一覧の取得で止まる", { harness.source.catalogGate.isWaiting }) else { return }

        run.cancel()
        await assertEndedWithoutCompletion(run)
        harness.source.catalogGate.open()
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertTrue(harness.source.downloadedEntries.isEmpty)
        XCTAssertTrue(harness.datasets.begunIDs.isEmpty)
        harness.assertNothingLeftBehind(previouslyActive: previous)
    }

    /// ダウンロード中に取り消すと、版を始めず、有効化もしません。
    ///
    /// 責務: ダウンロードの段階の取り消しを確認します。
    func testCancellationWhileDownloadingStopsBeforeBeginImport() async throws {
        harness.source.downloadGate.close()
        let run = startConsuming()
        guard await harness.waitUntil("ダウンロードで止まる", { harness.source.downloadGate.isWaiting }) else { return }

        run.cancel()
        await assertEndedWithoutCompletion(run)
        guard await harness.waitUntil("ダウンロードが取り消しで終わる", { !harness.source.downloadGate.isWaiting }) else { return }
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertTrue(harness.datasets.begunIDs.isEmpty)
        XCTAssertTrue(harness.datasets.activations.isEmpty)
        harness.assertNothingLeftBehind(previouslyActive: previous)
    }

    /// 読みながら書いている途中で取り消すと、次の書き込みで止まり、有効化せず、途中の版を破棄し、ZIP を消します。
    ///
    /// 責務: 取り込みの段階の取り消し(書くたびの確認)を確認します。
    func testCancellationWhileImportingDiscardsDatasetAndRemovesArchive() async throws {
        var script = RoadRegulationImportHarness.defaultScript()
        script.records = (0..<5).map { .regulation(Values.eastwardLineDraft("K\($0)")) }
        script.blockBeforeRecordIndex = 1
        harness.reader.replaceScript(script)
        let run = startConsuming(batchSize: 2)
        guard await harness.waitUntil("読み取りで止まる", { harness.reader.gate.isWaiting }) else { return }

        run.cancel()
        harness.reader.gate.open()
        await assertEndedWithoutCompletion(run)
        guard await harness.waitUntil("途中の版の破棄と ZIP の削除", {
            harness.datasets.begunIDs.count == 1 && harness.datasets.importingDatasetIDs.isEmpty && harness.source.remainingFiles.isEmpty
        }) else { return }
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertTrue(harness.datasets.activations.isEmpty)
        XCTAssertLessThan(harness.reader.consumedCount, 5, "取り消しの後も最後まで読みました")
        harness.assertNothingLeftBehind(previouslyActive: previous)
    }
}

import Foundation
import XCTest
@testable import ProjectZD8

/// 取り込みのユースケースを偽物だけで組み立て、通知を期限つきで集め、「途中の状態を残さない」ことを確かめる補助です。
///
/// 一時ファイルのフォルダを作り、`tearDown()` で門を開いてからフォルダを消します。
@MainActor
final class RoadRegulationImportHarness {
    /// 取り込み1回の結果です(通知と、失敗の種類)。
    nonisolated struct Outcome: Sendable {
        /// 失敗の種類です。
        nonisolated enum Failure: Equatable, Sendable {
            /// 取り込みのエラー。
            case importError(RoadRegulationImportError)
            /// 取り消し(`CancellationError`)。
            case cancellation
            /// それ以外のエラー(説明の文字列)。
            case other(String)
        }

        /// 受け取った通知(受け取った順)です。
        let events: [RoadRegulationImportEvent]
        /// 失敗の種類です。成功なら `nil`。
        let failure: Failure?
    }

    /// 対象の県(沖縄)です。
    static let prefecture = RoadRegulationTestValues.prefecture(47)
    /// ダウンロード前の確認の境界(100 MB。MB は 1,000,000 バイト)です。
    static let minimumBytesBeforeDownload: Int64 = 100_000_000
    /// ダウンロード後の確認の足し分(50 MB)です。
    static let marginBytesAfterDownload: Int64 = 50_000_000

    /// 呼び出しの帳面です。
    let log = RoadRegulationImportCallLog()
    /// 一時ファイルのフォルダです。
    let directory: URL
    /// 配布元の偽物です。
    let source: RoadRegulationSourceFake
    /// 読み取りの偽物です。
    let reader: RoadRegulationArchiveReaderFake
    /// 空き容量の偽物です。
    let capacity: RoadRegulationStorageCapacityFake
    /// 版の Repository の Spy です。
    let datasets: RoadRegulationDatasetRepositorySpy

    /// 責務: 一時フォルダと偽物を用意します(空き容量は十分、一覧は沖縄だけ、読み取りは既定の台本)。
    init(archiveByteCount: Int = 1_000) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RoadRegulationImport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        source = RoadRegulationSourceFake(
            catalog: RoadRegulationTestValues.catalog([Self.prefecture]), downloadDirectory: directory,
            archiveByteCount: archiveByteCount, log: log
        )
        reader = RoadRegulationArchiveReaderFake(script: Self.defaultScript(), log: log)
        capacity = RoadRegulationStorageCapacityFake(beforeDownload: 10_000_000_000, afterDownload: 10_000_000_000, log: log)
        datasets = RoadRegulationDatasetRepositorySpy(log: log)
    }

    /// 責務: 止めた偽物を再開させ、一時フォルダを消します。
    func tearDown() {
        source.catalogGate.open()
        source.downloadGate.open()
        reader.gate.open()
        try? FileManager.default.removeItem(at: directory)
    }

    /// 既定の台本の規制(線と一時停止)です。
    static let defaultRegulations = [
        RoadRegulationTestValues.eastwardLineDraft("LINE-1"),
        RoadRegulationTestValues.stopDraft("STOP-1", at: RoadRegulationTestValues.offset(east: 500, north: 200)),
    ]

    /// 責務: 既定の読み取りの台本(進捗2回、規制2件と読み飛ばし1件、基準月 2026-09・版 k_2.1・3行)を作ります。
    static func defaultScript() -> RoadRegulationArchiveReaderFake.Script {
        RoadRegulationArchiveReaderFake.Script(
            progressSteps: [
                RoadRegulationArchiveReadProgress(processedCompressedBytes: 500, totalCompressedBytes: 1_000),
                RoadRegulationArchiveReadProgress(processedCompressedBytes: 1_000, totalCompressedBytes: 1_000),
            ],
            records: defaultRegulations.map { .regulation($0) } + [.skipped(.outOfScopeKind)],
            summary: RoadRegulationArchiveSummary(dataMonth: RoadRegulationTestValues.month(2026, 9), formatVersion: "k_2.1", totalRows: 3)
        )
    }

    /// 責務: 偽物から取り込みのユースケースを作ります(時刻は固定)。
    func makeUseCase(batchSize: Int = 1_000) -> ImportRoadRegulationDatasetUseCase {
        ImportRoadRegulationDatasetUseCase(
            source: source, archiveReader: reader, datasets: datasets, capacity: capacity,
            grid: RoadRegulationGrid(), batchSize: batchSize, now: { RoadRegulationTestValues.fixedNow }
        )
    }

    /// 責務: 通知の列を最後まで(期限つきで)集めます。期限を超えたら `XCTFail` して `nil` を返します。
    func run(
        catalog: RoadRegulationCatalog? = nil,
        batchSize: Int = 1_000,
        on testCase: XCTestCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> Outcome? {
        let stream = makeUseCase(batchSize: batchSize).events(for: Self.prefecture, catalog: catalog)
        let runner = TestBoundedAsyncRun<Outcome> { await Self.collect(stream) }
        return await runner.value(on: testCase, file: file, line: line)
    }

    /// 責務: `run` を呼び、期限切れ(`nil`)ならテストを失敗として投げます。
    func runOrFail(
        catalog: RoadRegulationCatalog? = nil,
        batchSize: Int = 1_000,
        on testCase: XCTestCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> Outcome {
        let outcome = await run(catalog: catalog, batchSize: batchSize, on: testCase, file: file, line: line)
        return try XCTUnwrap(outcome, "取り込みが期限内に終わりませんでした", file: file, line: line)
    }

    /// 責務: 通知の列を集め、失敗を種類に分けます。
    nonisolated static func collect(_ stream: AsyncThrowingStream<RoadRegulationImportEvent, any Error>) async -> Outcome {
        var events: [RoadRegulationImportEvent] = []
        do {
            for try await event in stream { events.append(event) }
            return Outcome(events: events, failure: nil)
        } catch let error as RoadRegulationImportError {
            return Outcome(events: events, failure: .importError(error))
        } catch is CancellationError {
            return Outcome(events: events, failure: .cancellation)
        } catch {
            return Outcome(events: events, failure: .other(String(describing: error)))
        }
    }

    /// 責務: 取り込みが失敗した後に、有効な版が変わらず、途中の版とダウンロードしたファイルが残っていないことを確かめます。
    /// - Parameter previouslyActive: 取り込みの前に有効だった版。
    func assertNothingLeftBehind(previouslyActive: [RoadRegulationDataset], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(datasets.currentActiveDatasets, previouslyActive, "有効な版が変わりました", file: file, line: line)
        XCTAssertTrue(datasets.importingDatasetIDs.isEmpty, "取り込み途中の版が残っています", file: file, line: line)
        XCTAssertTrue(source.remainingFiles.isEmpty, "ダウンロードしたファイルが残っています", file: file, line: line)
        XCTAssertEqual(Set(source.removedURLs), Set(source.createdURLs), "作ったファイルの削除を頼んでいません", file: file, line: line)
    }

    /// 責務: 沖縄に有効な版を1つ種として入れ、それを返します。
    @discardableResult
    func seedPreviousActive() -> RoadRegulationDataset {
        let dataset = RoadRegulationTestValues.dataset(Self.prefecture)
        datasets.seedActive(dataset)
        return dataset
    }

    /// 責務: 条件が成り立つまで期限(2秒)つきで待ちます。
    func waitUntil(_ description: String, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async -> Bool {
        await LocationRecordingBoundedWaiter.waitUntil(description, file: file, line: line, condition: condition)
    }
}

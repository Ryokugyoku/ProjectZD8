import Foundation
import XCTest
@testable import ProjectZD8

/// `ImportRoadRegulationDatasetUseCase` の空き容量の確認(ダウンロード前は 100 MB 以上、ダウンロード後は ZIP の大きさ × 3 + 50 MB 以上)を、
/// 境界のちょうどと1バイト不足で検証します。MB は 1,000,000 バイトとして計算します(設計書は2進の単位を MiB と書き分けているため)。
@MainActor
final class ImportRoadRegulationDatasetUseCaseCapacityTests: XCTestCase {
    private typealias Harness = RoadRegulationImportHarness
    /// ダウンロードで作る ZIP の大きさです。
    private static let archiveBytes = 1_000
    /// ダウンロード後に必要な空き容量(1,000 × 3 + 50,000,000)です。
    private static let requiredAfterDownload: Int64 = 3_000 + Harness.marginBytesAfterDownload

    private var harness: RoadRegulationImportHarness!
    private var previous: [RoadRegulationDataset] = []

    override func setUp() async throws {
        try await super.setUp()
        harness = try RoadRegulationImportHarness(archiveByteCount: Self.archiveBytes)
        previous = [harness.seedPreviousActive()]
    }

    override func tearDown() async throws {
        harness.tearDown()
        harness = nil
        try await super.tearDown()
    }

    /// ダウンロード前がちょうど 100 MB、ダウンロード後がちょうど必要量なら、取り込めます。
    ///
    /// 責務: 両方の境界のちょうどが「足りる」ことを確認します。
    func testExactBoundariesAreEnough() async throws {
        harness.capacity.set(beforeDownload: Harness.minimumBytesBeforeDownload, afterDownload: Self.requiredAfterDownload)

        let outcome = try await harness.runOrFail(on: self)

        XCTAssertNil(outcome.failure)
        XCTAssertEqual(harness.datasets.activations.count, 1)
    }

    /// ダウンロード前が 100 MB に1バイト足りないと `insufficientStorage` で、ダウンロードを呼びません。
    ///
    /// 責務: ダウンロード前の確認の1バイト不足を確認します。
    func testOneByteShortBeforeDownloadSkipsDownload() async throws {
        harness.capacity.set(beforeDownload: Harness.minimumBytesBeforeDownload - 1, afterDownload: Self.requiredAfterDownload)

        let outcome = try await harness.runOrFail(on: self)

        XCTAssertEqual(outcome.failure, .importError(.insufficientStorage))
        XCTAssertTrue(harness.source.downloadedEntries.isEmpty)
        XCTAssertTrue(harness.datasets.begunIDs.isEmpty)
        harness.assertNothingLeftBehind(previouslyActive: previous)
    }

    /// ダウンロード後が必要量に1バイト足りないと `insufficientStorage` で、版を始めず(破棄もせず)、ZIP だけを消します。
    ///
    /// 責務: ダウンロード後の確認の1バイト不足を確認します。
    func testOneByteShortAfterDownloadRemovesArchive() async throws {
        harness.capacity.set(beforeDownload: Harness.minimumBytesBeforeDownload, afterDownload: Self.requiredAfterDownload - 1)

        let outcome = try await harness.runOrFail(on: self)

        XCTAssertEqual(outcome.failure, .importError(.insufficientStorage))
        XCTAssertEqual(harness.source.createdURLs.count, 1)
        XCTAssertTrue(harness.datasets.activations.isEmpty)
        XCTAssertTrue(harness.reader.readURLs.isEmpty, "容量不足なのに読み始めました")
        XCTAssertTrue(harness.datasets.begunIDs.isEmpty, "容量の確認より前に版を始めました")
        XCTAssertTrue(harness.datasets.discardedIDs.isEmpty, "始めていない版を破棄しました")
        harness.assertNothingLeftBehind(previouslyActive: previous)
    }

    /// ダウンロード後の必要量は ZIP の大きさに比例します(大きさ 2,000,000 B なら 56,000,000 B が境界)。
    ///
    /// 責務: 「× 3」の係数を、別の大きさの ZIP の境界で確認します。
    func testAfterDownloadRequirementScalesWithArchiveSize() async throws {
        let required: Int64 = 6_000_000 + Harness.marginBytesAfterDownload

        let short = try await runWithLargeArchive(afterDownload: required - 1)
        let enough = try await runWithLargeArchive(afterDownload: required)

        XCTAssertEqual(short?.failure, .importError(.insufficientStorage))
        XCTAssertNotNil(enough)
        XCTAssertNil(enough?.failure)
    }

    /// 責務: 大きさ 2,000,000 B の ZIP を作る新しい組み立てで1回取り込み、結果を返します(帳面を前の実行と分けるため)。
    private func runWithLargeArchive(afterDownload: Int64) async throws -> RoadRegulationImportHarness.Outcome? {
        harness.tearDown()
        harness = try RoadRegulationImportHarness(archiveByteCount: 2_000_000)
        harness.capacity.set(beforeDownload: Harness.minimumBytesBeforeDownload, afterDownload: afterDownload)
        return await harness.run(on: self)
    }
}

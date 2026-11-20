import Foundation
import XCTest
@testable import ProjectZD8

/// `RoadRegulationImportBatchWriter` の、件数ごとのまとめ書き(境界 999 / 1,000 / 1,001)・升目の付与・件数と理由の集計・範囲を検証します。
@MainActor
final class RoadRegulationImportBatchWriterTests: XCTestCase {
    private typealias Values = RoadRegulationTestValues

    private var repository: RoadRegulationDatasetRepositorySpy!
    private var datasetID: RoadRegulationDatasetID!

    override func setUp() async throws {
        try await super.setUp()
        repository = RoadRegulationDatasetRepositorySpy()
        datasetID = try repository.beginImport(RoadRegulationDatasetDraft(
            prefecture: Values.prefecture(47), publicationStamp: Values.publicationStamp,
            sourceURL: Values.archiveURL(Values.prefecture(47)), downloadedAt: Values.fixedNow
        ))
    }

    override func tearDown() async throws {
        repository = nil
        datasetID = nil
        try await super.tearDown()
    }

    /// 責務: 検証対象の書き込み器を作ります。
    private func makeWriter(batchSize: Int) -> RoadRegulationImportBatchWriter {
        RoadRegulationImportBatchWriter(datasetID: datasetID, repository: repository, grid: RoadRegulationGrid(), batchSize: batchSize)
    }

    /// 責務: ユニークキーの異なる一時停止の記録を `count` 件作ります。
    private func stopRecords(_ count: Int, prefix: String = "S") -> [RoadRegulationArchiveRecord] {
        (0..<count).map { .regulation(Values.stopDraft("\(prefix)\($0)", at: Values.offset(east: Double($0), north: 0))) }
    }

    /// 責務: 空でない書き込みのまとまりの件数を返します。
    private var batchSizes: [Int] {
        repository.appendedBatches.map(\.count).filter { $0 > 0 }
    }

    /// batchSize = 2 で5件なら、受け取りの途中で 2・2 件を書き、最後に1件を書きます。
    ///
    /// 責務: まとまりの境目と、残りを `finish` で書くことを確認します。
    func testWritesFullBatchesWhileAcceptingAndRemainderOnFinish() throws {
        var writer = makeWriter(batchSize: 2)

        for record in stopRecords(5) { try writer.accept(record) }
        XCTAssertEqual(batchSizes, [2, 2])
        XCTAssertEqual(writer.importedCount, 4)

        _ = try writer.finish(totalRows: 5)
        XCTAssertEqual(batchSizes, [2, 2, 1])
        XCTAssertEqual(writer.importedCount, 5)
    }

    /// 1,000件ごとのまとめで、999件は `finish` まで書かず、最後に999件を1回で書きます。
    ///
    /// 責務: 境界の1件手前を確認します。
    func testNineHundredNinetyNineRecordsAreWrittenOnceOnFinish() throws {
        var writer = makeWriter(batchSize: 1_000)

        for record in stopRecords(999) { try writer.accept(record) }
        XCTAssertEqual(batchSizes, [])

        _ = try writer.finish(totalRows: 999)
        XCTAssertEqual(batchSizes, [999])
    }

    /// 1,000件ちょうどは、1,000件目を受け取った時に1回で書き、`finish` で書き足すものはありません。
    ///
    /// 責務: 境界のちょうどを確認します。
    func testOneThousandRecordsAreWrittenWhenTheBatchFills() throws {
        var writer = makeWriter(batchSize: 1_000)

        for record in stopRecords(1_000) { try writer.accept(record) }
        XCTAssertEqual(batchSizes, [1_000])

        let result = try writer.finish(totalRows: 1_000)
        XCTAssertEqual(batchSizes, [1_000])
        XCTAssertEqual(result.counts.importedRegulations, 1_000)
    }

    /// 1,001件は、1,000件を書き、`finish` で残りの1件を書きます。
    ///
    /// 責務: 境界の1件超過を確認します。
    func testOneThousandOneRecordsWriteOneThousandThenOne() throws {
        var writer = makeWriter(batchSize: 1_000)

        for record in stopRecords(1_001) { try writer.accept(record) }
        XCTAssertEqual(batchSizes, [1_000])

        let result = try writer.finish(totalRows: 1_001)
        XCTAssertEqual(batchSizes, [1_000, 1])
        XCTAssertEqual(result.counts.importedRegulations, 1_001)
    }

    /// 読み飛ばしと破棄は書かずに、種類と理由ごとに数え、行数は `finish` に渡した値になります。
    ///
    /// 責務: 件数の集計(読み飛ばし2種・破棄の理由ごと・取り込み件数・行数)を確認します。
    func testCountsSkippedAndRejectedRecordsByReason() throws {
        var writer = makeWriter(batchSize: 10)
        let records: [RoadRegulationArchiveRecord] = [
            .skipped(.outOfScopeKind), .skipped(.outOfScopeKind), .skipped(.abolished),
            .rejected(.invalidSpeed), .rejected(.fieldCountMismatch), .rejected(.fieldCountMismatch),
        ] + stopRecords(3)

        for record in records { try writer.accept(record) }
        let result = try writer.finish(totalRows: 9)

        XCTAssertEqual(result.counts.totalRows, 9)
        XCTAssertEqual(result.counts.importedRegulations, 3)
        XCTAssertEqual(result.counts.skippedOutOfScope, 2)
        XCTAssertEqual(result.counts.skippedAbolished, 1)
        XCTAssertEqual(result.counts.rejectedByReason[.invalidSpeed], 1)
        XCTAssertEqual(result.counts.rejectedByReason[.fieldCountMismatch], 2)
        XCTAssertEqual(result.counts.rejectedRows, 3)
        XCTAssertEqual(repository.appendedBatches.flatMap { $0 }.count, 3)
    }

    /// 挿入されなかった(同じユニークキーの)件数は `duplicateUniqueKey` として数え、取り込み件数に入れません(まとまりをまたいでも同じ)。
    ///
    /// 責務: 重複の数え方を確認します。
    func testDuplicatesAcrossBatchesAreCountedAsRejected() throws {
        var writer = makeWriter(batchSize: 2)
        let keys = ["A", "B", "A", "C", "B"]

        for key in keys { try writer.accept(.regulation(Values.stopDraft(key))) }
        let result = try writer.finish(totalRows: keys.count)

        XCTAssertEqual(result.counts.importedRegulations, 3)
        XCTAssertEqual(writer.importedCount, 3)
        XCTAssertEqual(result.counts.rejectedByReason[.duplicateUniqueKey], 2)
        XCTAssertEqual(result.counts.rejectedRows, 2)
    }

    /// 升目へ割り当てられない(10,000 升を超える)面は書かずに `geometryTooLarge` として破棄に数えます。
    ///
    /// 責務: 大きすぎる形状の扱いを確認します。
    func testOversizedGeometryIsRejectedAsGeometryTooLarge() throws {
        var writer = makeWriter(batchSize: 10)

        try writer.accept(.regulation(Values.oversizedAreaDraft("HUGE")))
        try writer.accept(.regulation(Values.areaDraft("SMALL", sideMeters: 300)))
        let result = try writer.finish(totalRows: 2)

        XCTAssertEqual(result.counts.rejectedByReason[.geometryTooLarge], 1)
        XCTAssertEqual(result.counts.importedRegulations, 1)
        XCTAssertEqual(repository.appendedBatches.flatMap { $0 }.map(\.draft.uniqueKey), ["SMALL"])
    }

    /// 書く規制には、停止点と進入方向の点の升目が、昇順・重複なしで付きます。
    ///
    /// 責務: 既知の座標の升目(key 1,828,044,883)と、升目の並びを確認します。
    func testAttachesSortedUniqueCellsIncludingStopAndApproach() throws {
        var writer = makeWriter(batchSize: 10)
        let stop = Values.coordinate(latitude: 26.2231795618476, longitude: 127.719496353425)
        let draft = Values.stopDraft("KNOWN", at: stop, approachMeters: 600)
        let approach = try XCTUnwrap(draft.geometry.approachPoints.first)

        try writer.accept(.regulation(draft))
        _ = try writer.finish(totalRows: 1)

        let cells = try XCTUnwrap(repository.appendedBatches.first?.first?.cells)
        let approachKey = RoadRegulationCellKey(
            row: Int(((approach.latitude + 90) * 240).rounded(.down)), column: Int(((approach.longitude + 180) * 160).rounded(.down))
        )
        XCTAssertTrue(cells.contains(RoadRegulationCellKey(row: 27_893, column: 49_235)))
        XCTAssertEqual(RoadRegulationCellKey(row: 27_893, column: 49_235).rawValue, 1_828_044_883)
        XCTAssertTrue(cells.contains(approachKey))
        XCTAssertNotEqual(approachKey, RoadRegulationCellKey(row: 27_893, column: 49_235))
        XCTAssertEqual(cells, Array(Set(cells)).sorted())
        XCTAssertEqual(repository.appendedBatches.first?.first?.draft, draft)
    }

    /// 範囲(外接矩形)は、書いた全規制の形状(主の点と進入方向の点)の和です。
    ///
    /// 責務: 手で求めた最小・最大の緯度経度と一致することを確認します。
    func testCoverageIsUnionOfAllRegulations() throws {
        var writer = makeWriter(batchSize: 2)
        let line = Values.lineDraft("LINE", points: [
            Values.coordinate(latitude: 26.10, longitude: 127.60), Values.coordinate(latitude: 26.12, longitude: 127.65),
        ])
        let stop = Values.stopDraft("STOP", at: Values.coordinate(latitude: 26.30, longitude: 127.80), approachMeters: 20)
        let area = Values.areaDraft("AREA", southWest: Values.coordinate(latitude: 26.05, longitude: 127.70), sideMeters: 200)
        let points = [line, stop, area].flatMap { $0.geometry.mainParts.flatMap { $0 } + $0.geometry.approachPoints }

        for draft in [line, stop, area] { try writer.accept(.regulation(draft)) }
        let result = try writer.finish(totalRows: 3)

        XCTAssertEqual(result.coverage, Values.box(
            minLatitude: 26.05, maxLatitude: try XCTUnwrap(points.map(\.latitude).max()),
            minLongitude: 127.60, maxLongitude: try XCTUnwrap(points.map(\.longitude).max())
        ))
        XCTAssertGreaterThan(try XCTUnwrap(points.map(\.latitude).max()), 26.30)
    }

    /// 規制が1件も無ければ範囲は `nil` です。
    ///
    /// 責務: 範囲を作れない時に推測の値を入れないことを確認します。
    func testCoverageIsNilWithoutRegulations() throws {
        var writer = makeWriter(batchSize: 2)

        try writer.accept(.skipped(.abolished))
        let result = try writer.finish(totalRows: 1)

        XCTAssertNil(result.coverage)
        XCTAssertEqual(result.counts.importedRegulations, 0)
        XCTAssertEqual(batchSizes, [])
    }

    /// 書き込みの失敗は、受け取りから投げられます。
    ///
    /// 責務: 保存の失敗を握りつぶさないことを確認します。
    func testRepositoryFailureIsThrownFromAccept() throws {
        repository.fail(.appendRegulations, with: .storageFull)
        var writer = makeWriter(batchSize: 2)
        let records = stopRecords(2)

        try writer.accept(records[0])
        XCTAssertThrowsError(try writer.accept(records[1]))
    }

    /// batchSize が1未満なら1として扱い、1件ごとに書きます。
    ///
    /// 責務: batchSize の下限を確認します。
    func testBatchSizeBelowOneWritesEachRecord() throws {
        var writer = makeWriter(batchSize: 0)

        for record in stopRecords(3) { try writer.accept(record) }

        XCTAssertEqual(batchSizes, [1, 1, 1])
    }
}

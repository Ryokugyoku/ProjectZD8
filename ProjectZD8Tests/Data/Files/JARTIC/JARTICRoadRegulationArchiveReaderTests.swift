import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICRoadRegulationArchiveReader` が、テストで組み立てた ZIP から記録を行の順に渡し、要約・進捗を正しく返すことを検証します。
///
/// 形式の失敗は `JARTICRoadRegulationArchiveReaderRejectionTests` で検証します。
@MainActor
final class JARTICRoadRegulationArchiveReaderTests: XCTestCase {
    private typealias Fixture = JARTICCSVFixture
    private typealias Row = JARTICCSVFixture.Row

    /// 読み取り1回の結果です。
    private struct Reading {
        let records: [RoadRegulationArchiveRecord]
        let summary: RoadRegulationArchiveSummary
        let progress: [RoadRegulationArchiveReadProgress]
    }

    private var files: JARTICArchiveTemporaryFiles!

    override func setUp() async throws {
        try await super.setUp()
        files = try JARTICArchiveTemporaryFiles()
    }

    override func tearDown() async throws {
        files.removeAll()
        files = nil
        try await super.tearDown()
    }

    /// 責務: ZIP を一時ファイルへ書いて読み、渡された記録・要約・進捗を返します。
    private func read(_ archive: [UInt8]) throws -> Reading {
        let url = try files.write(archive)
        var records: [RoadRegulationArchiveRecord] = []
        var progress: [RoadRegulationArchiveReadProgress] = []
        let summary = try JARTICRoadRegulationArchiveReader().read(
            archiveAt: url, progress: { progress.append($0) }, consume: { records.append($0) }
        )
        return Reading(records: records, summary: summary, progress: progress)
    }

    /// 責務: 記録が規制なら、そのユニークキーと種別を返します。
    private func regulationKey(_ record: RoadRegulationArchiveRecord) -> (String, RoadRegulationKind)? {
        guard case .regulation(let draft) = record else { return nil }
        return (draft.uniqueKey, draft.kind)
    }

    /// 見本と同じ形の ZIP(フォルダ + `沖縄県警_202609_k_2.1.csv`)から、採用・読み飛ばし・破棄が行の順に、正しい件数で渡ります。
    ///
    /// 責務: 記録の順と種類、要約の基準月 2026-09・版 k_2.1・行数を確認します。
    func testPassesAdoptedSkippedAndRejectedRecordsInRowOrder() throws {
        let rows = [
            Row(kind: 112, [JARTICColumnName.uniqueKey: "A-112"]),
            Row(kind: 1, [JARTICColumnName.uniqueKey: "OUT-OF-SCOPE"]),
            Row(kind: 112, [JARTICColumnName.uniqueKey: "ABOLISHED", JARTICColumnName.abolishedOn: "20250101"]),
            Row(kind: 112, [JARTICColumnName.uniqueKey: "BAD-SPEED", JARTICColumnName.speed: "0"]),
            Row(kind: 112, [JARTICColumnName.uniqueKey: "SHORT"], fieldCountOffset: -1),
            Row(kind: 63, [JARTICColumnName.uniqueKey: "B-63"]),
        ]

        let reading = try read(Fixture.archive(csv: Fixture.csv(rows)))

        XCTAssertEqual(reading.records.count, 6)
        XCTAssertEqual(regulationKey(reading.records[0])?.0, "A-112")
        XCTAssertEqual(regulationKey(reading.records[0])?.1, .speedLimitSection)
        XCTAssertEqual(reading.records[1], .skipped(.outOfScopeKind))
        XCTAssertEqual(reading.records[2], .skipped(.abolished))
        XCTAssertEqual(reading.records[3], .rejected(.invalidSpeed))
        XCTAssertEqual(reading.records[4], .rejected(.fieldCountMismatch))
        XCTAssertEqual(regulationKey(reading.records[5])?.0, "B-63")
        XCTAssertEqual(regulationKey(reading.records[5])?.1, .stop)
        XCTAssertEqual(reading.summary.dataMonth, RoadRegulationTestValues.month(2026, 9))
        XCTAssertEqual(reading.summary.formatVersion, "k_2.1")
        XCTAssertEqual(reading.summary.totalRows, 6)
    }

    /// 採用した規制の値が、行の値から作られます(速度と形状)。
    ///
    /// 責務: 最高速度の値と、線の2点が記録に入ることを確認します。
    func testAdoptedRegulationCarriesRowValues() throws {
        let rows = [Row(kind: 112, [JARTICColumnName.uniqueKey: "SPEED-60", JARTICColumnName.speed: "60",
                                    JARTICColumnName.coordinates: "127.71 26.21;127.72 26.22"])]

        let reading = try read(Fixture.archive(csv: Fixture.csv(rows)))

        guard case .regulation(let draft) = try XCTUnwrap(reading.records.first) else {
            return XCTFail("規制として採用されませんでした: \(reading.records)")
        }
        XCTAssertEqual(draft.speedLimitKph, 60)
        XCTAssertEqual(draft.geometry.mainParts, [[
            RoadRegulationTestValues.coordinate(latitude: 26.21, longitude: 127.71),
            RoadRegulationTestValues.coordinate(latitude: 26.22, longitude: 127.72),
        ]])
    }

    /// 格納(方式0)の CSV も読めて、結果は deflate の時と同じです。
    ///
    /// 責務: 圧縮方式に結果が依存しないことを確認します。
    func testStoredAndDeflatedArchivesGiveSameRecords() throws {
        let csv = Fixture.csv(Fixture.speedLimitRows(count: 5) + [Row(kind: 1)])

        let deflated = try read(Fixture.archive(csv: csv, compression: .deflate))
        let stored = try read(Fixture.archive(csv: csv, compression: .stored))

        XCTAssertEqual(stored.records, deflated.records)
        XCTAssertEqual(stored.summary, deflated.summary)
        XCTAssertEqual(stored.records.count, 6)
    }

    /// 拡張子が大文字(`.CSV`)でも CSV のエントリとして扱います。
    ///
    /// 責務: `.csv` の大小文字を区別しないことを確認します。
    func testAcceptsUppercaseCSVExtension() throws {
        let csv = Fixture.csv(Fixture.speedLimitRows(count: 2))

        let reading = try read(Fixture.archive(csv: csv, entryName: "typeD_okinawa/沖縄県警_202609_k_2.1.CSV"))

        XCTAssertEqual(reading.summary.totalRows, 2)
        XCTAssertEqual(reading.summary.dataMonth, RoadRegulationTestValues.month(2026, 9))
    }

    /// フォルダのエントリが CSV の前後にいくつあっても飛ばします。
    ///
    /// 責務: 名前が `/` で終わるエントリを CSV として数えないことを確認します。
    func testSkipsDirectoryEntries() throws {
        let csv = Fixture.csv(Fixture.speedLimitRows(count: 3))
        let archive = TestZipArchiveBuilder(entries: [
            .directory("typeD_okinawa/"), .directory("typeD_okinawa/sub.csv/"),
            Fixture.csvEntry(Fixture.okinawaEntryName, csv), .directory("other/"),
        ]).build()

        let reading = try read(archive)

        XCTAssertEqual(reading.records.count, 3)
        XCTAssertEqual(reading.summary.totalRows, 3)
    }

    /// エントリ名に基準月の印が無い時、基準月は `nil` です(一覧の基準月で補うのは取り込みの側)。
    ///
    /// 責務: 名前から基準月を取れない時に、推測の値を入れないことを確認します。
    func testEntryNameWithoutMonthGivesNilDataMonth() throws {
        let csv = Fixture.csv(Fixture.speedLimitRows(count: 1))

        let reading = try read(Fixture.archive(csv: csv, entryName: "typeD_okinawa/regulations.csv"))

        XCTAssertNil(reading.summary.dataMonth)
        XCTAssertEqual(reading.summary.formatVersion, "k_2.1")
    }

    /// 空行は行として数えません。
    ///
    /// 責務: 行の間と末尾の空行が記録にも行数にも入らないことを確認します。
    func testBlankLinesAreNotCounted() throws {
        var csv = Fixture.encodeLine(Fixture.columnNames)
        csv += Fixture.encodeLine(Fixture.fields(of: Row(kind: 112, [JARTICColumnName.uniqueKey: "K1"])))
        csv += [0x0D, 0x0A]
        csv += Fixture.encodeLine(Fixture.fields(of: Row(kind: 112, [JARTICColumnName.uniqueKey: "K2"])))
        csv += [0x0D, 0x0A, 0x0D, 0x0A]

        let reading = try read(Fixture.archive(csv: csv))

        XCTAssertEqual(reading.records.count, 2)
        XCTAssertEqual(reading.summary.totalRows, 2)
    }

    /// 進捗は単調に増え、全体の大きさは CSV のエントリの圧縮サイズで、処理済みがそれを超えません。
    ///
    /// 責務: 64 KiB を超える格納の CSV で、進捗が複数回・単調に通知されることを確認します。
    func testProgressIncreasesMonotonically() throws {
        let csv = Fixture.csv(Fixture.speedLimitRows(count: 2_000))
        XCTAssertGreaterThan(csv.count, 4 * 65_536)

        let reading = try read(Fixture.archive(csv: csv, compression: .stored))

        let processed = reading.progress.map(\.processedCompressedBytes)
        XCTAssertGreaterThanOrEqual(processed.count, 2)
        XCTAssertEqual(processed, processed.sorted())
        XCTAssertTrue(reading.progress.allSatisfy { $0.totalCompressedBytes == Int64(csv.count) })
        XCTAssertTrue(processed.allSatisfy { $0 >= 0 && $0 <= Int64(csv.count) })
        XCTAssertGreaterThan(processed.last ?? 0, 0)
    }

    /// `consume` が投げた `CancellationError` がそのまま伝わり、その後の記録は渡されません。
    ///
    /// 責務: 取り消しで読み取りが止まることを確認します。
    func testCancellationFromConsumePropagates() throws {
        let url = try files.write(Fixture.archive(csv: Fixture.csv(Fixture.speedLimitRows(count: 10))))
        var consumed = 0

        XCTAssertThrowsError(try JARTICRoadRegulationArchiveReader().read(archiveAt: url, progress: { _ in }, consume: { _ in
            consumed += 1
            if consumed == 2 { throw CancellationError() }
        })) { error in
            XCTAssertTrue(error is CancellationError, "取り消しが別のエラーになりました: \(error)")
        }
        XCTAssertEqual(consumed, 2)
    }

    /// `consume` が投げたそれ以外のエラーも、置き換えずにそのまま伝わります。
    ///
    /// 責務: 書き込み側のエラーが形式の失敗に変わらないことを確認します。
    func testOtherErrorFromConsumePropagatesUnchanged() throws {
        let url = try files.write(Fixture.archive(csv: Fixture.csv(Fixture.speedLimitRows(count: 3))))

        XCTAssertThrowsError(try JARTICRoadRegulationArchiveReader().read(archiveAt: url, progress: { _ in }, consume: { _ in
            throw RoadRegulationRepositoryError.storageFull
        })) { error in
            XCTAssertEqual(error as? RoadRegulationRepositoryError, .storageFull)
        }
    }

    /// 数万行の入力でも、期限内に全行を読み終えます。
    ///
    /// 責務: 2万行(deflate)を別スレッドで読み、期限(60秒)内に行数と採用件数が揃うことを確認します。
    func testLargeInputFinishesWithinTimeLimit() throws {
        let rowCount = 20_000
        let url = try files.write(Fixture.archive(csv: Fixture.csv(Fixture.speedLimitRows(count: rowCount))))

        let result = TestBoundedExecution.run(on: self, seconds: 60) { () -> [Int]? in
            var adopted = 0
            let summary = try? JARTICRoadRegulationArchiveReader().read(archiveAt: url, progress: { _ in }, consume: { record in
                if case .regulation = record { adopted += 1 }
            })
            return summary.map { [$0.totalRows, adopted] }
        }

        XCTAssertEqual(result ?? nil, [rowCount, rowCount])
    }

    /// 見出しだけでデータ行の無い CSV は、読み取りとしては成功し、記録0件・行数0のまとめを返します。
    ///
    /// 責務: 件数0の判定を取り込みの側へ任せることを確認します。
    func testHeaderOnlyCSVReturnsEmptySummary() throws {
        let reading = try read(Fixture.archive(csv: Fixture.csv([])))

        XCTAssertTrue(reading.records.isEmpty)
        XCTAssertEqual(reading.summary.totalRows, 0)
        XCTAssertEqual(reading.summary.dataMonth, RoadRegulationTestValues.month(2026, 9))
    }
}

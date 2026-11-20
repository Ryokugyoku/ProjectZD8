import Foundation
import XCTest
@testable import ProjectZD8

/// `ZipEntryInflater` が、格納と deflate のエントリを正しく往復させ、CRC・進捗・受け手への受け渡しを仕様どおりに行うことを検証します。
@MainActor
final class ZipEntryInflaterTests: XCTestCase {
    /// 責務: 1ファイルの ZIP を作って展開し、元の中身と一致するかを期限つきで返します。
    private func roundTrips(_ content: [UInt8], _ compression: TestZipEntrySpec.Compression) -> Bool? {
        let zip = TestZipArchiveBuilder(entries: [.file("a.bin", content, compression)]).build()
        return TestBoundedExecution.run(on: self) {
            (try? TestZipExtraction.extractFile(zip))?.bytes == content
        }
    }

    /// 短い文字列が、格納でも deflate でも往復します。
    func testSmallContentRoundTripsForStoredAndDeflate() {
        let content = Array("hello, zip\r\n".utf8)
        XCTAssertEqual(roundTrips(content, .stored), true)
        XCTAssertEqual(roundTrips(content, .deflate), true)
    }

    /// 空のファイルが、格納でも deflate でも往復します(出力は空)。
    func testEmptyContentRoundTripsForStoredAndDeflate() {
        XCTAssertEqual(roundTrips([], .stored), true)
        XCTAssertEqual(roundTrips([], .deflate), true)
    }

    /// 圧縮率の高い数 MB の繰り返しデータが往復します。
    func testHighlyCompressibleMegabytesRoundTrip() {
        let content = TestZipSampleData.repetitive(count: 4_000_000)
        XCTAssertEqual(roundTrips(content, .deflate), true)
    }

    /// 圧縮の効かない数 MB の擬似乱数データが、deflate でも格納でも往復します。
    func testIncompressibleMegabytesRoundTrip() {
        let content = TestZipSampleData.pseudoRandom(count: 3_000_000, seed: 20_261_120)
        XCTAssertEqual(roundTrips(content, .deflate), true)
        XCTAssertEqual(roundTrips(content, .stored), true)
    }

    /// 入力・出力の塊の大きさ(1 B / 7 B / 既定など)を変えても、連結した結果が同じです。
    func testResultDoesNotDependOnChunkSizes() {
        let content = TestZipSampleData.repetitive(count: 12_000) + TestZipSampleData.pseudoRandom(count: 6_000, seed: 3)
        let sizes: [(Int, Int)] = [(65_536, 262_144), (1, 1), (7, 7), (1, 262_144), (4_093, 1), (65_536, 7), (3, 4_096)]
        for compression in [TestZipEntrySpec.Compression.deflate, .stored] {
            let zip = TestZipArchiveBuilder(entries: [.file("a.bin", content, compression)]).build()
            for (input, output) in sizes {
                let inflater = ZipEntryInflater(inputChunkSize: input, outputChunkSize: output)
                let result = TestBoundedExecution.run(on: self) {
                    try? TestZipExtraction.extractFile(zip, inflater: inflater).bytes
                }
                XCTAssertEqual(result, content, "\(compression) 入力\(input) 出力\(output)")
            }
        }
    }

    /// bit3(データ記述子)が立ち、局所ヘッダーの CRC・サイズが 0 でも、中央ディレクトリの値で往復します。
    func testDataDescriptorEntryRoundTrips() throws {
        let content = TestZipSampleData.repetitive(count: 3_000)
        var spec = TestZipEntrySpec.file("dd.txt", content)
        spec.usesDataDescriptor = true

        let result = try TestZipExtraction.extractFile(TestZipArchiveBuilder(entries: [spec]).build())

        XCTAssertEqual(result.bytes, content)
    }

    /// 局所ヘッダーの拡張フィールドが中央ディレクトリと違っても、本体の開始位置を正しく決めます。
    func testLocalExtraFieldDifferingFromCentralStillExtracts() throws {
        let content = Array("payload after a longer local extra field".utf8)
        let extra: [UInt8] = [0xFE, 0xCA, 0x04, 0x00, 1, 2, 3, 4]
        for compression in [TestZipEntrySpec.Compression.stored, .deflate] {
            var spec = TestZipEntrySpec.file("x.txt", content, compression)
            spec.localExtraField = extra

            let result = try TestZipExtraction.extractFile(TestZipArchiveBuilder(entries: [spec]).build())

            XCTAssertEqual(result.bytes, content, "\(compression)")
        }
    }

    /// フォルダと複数のファイルがあっても、名前で選んだエントリの中身が取れます(漢字の名前を含む)。
    func testExtractsTheRequestedEntryAmongSeveral() throws {
        var csv = TestZipEntrySpec.file("typeD_okinawa/沖縄県警_202609_k_2.1.csv", Array("csv body".utf8))
        csv.usesUTF8Flag = true
        let zip = TestZipArchiveBuilder(entries: [
            .directory("typeD_okinawa/"), .file("typeD_okinawa/readme.txt", Array("readme".utf8), .stored), csv
        ]).build()

        let result = try TestZipExtraction.extractFile(zip, named: "typeD_okinawa/沖縄県警_202609_k_2.1.csv")

        XCTAssertEqual(result.bytes, Array("csv body".utf8))
    }

    /// 進捗は単調に増え、最後の累計が圧縮サイズに一致します(格納・deflate)。
    func testProgressIsMonotonicAndEndsAtCompressedSize() throws {
        let content = TestZipSampleData.pseudoRandom(count: 50_000, seed: 9)
        for compression in [TestZipEntrySpec.Compression.stored, .deflate] {
            let zip = TestZipArchiveBuilder(entries: [.file("a.bin", content, compression)]).build()
            let entry = try XCTUnwrap(TestZipExtraction.entries(in: zip).first)
            let inflater = ZipEntryInflater(inputChunkSize: 4_096, outputChunkSize: 8_192)

            let result = try TestZipExtraction.extractFile(zip, inflater: inflater)

            XCTAssertEqual(result.progress.last, entry.compressedSize, "\(compression)")
            XCTAssertEqual(result.progress, result.progress.sorted(), "\(compression)")
            XCTAssertGreaterThan(result.progress.count, 1, "\(compression) 塊ごとに進捗が出ること")
        }
    }

    /// 受け手が投げたエラーは、そのまま呼び出し元へ伝わり、以降の塊は渡されません。
    func testConsumerErrorPropagatesAndStopsDelivery() throws {
        struct StopError: Error, Equatable {}
        let zip = TestZipArchiveBuilder(entries: [.file("a.bin", TestZipSampleData.repetitive(count: 5_000))]).build()
        var calls = 0

        XCTAssertThrowsError(try TestZipExtraction.withFile(zip) { handle in
            let entry = try XCTUnwrap(ZipCentralDirectoryReader().entries(in: handle).first)
            try ZipEntryInflater(outputChunkSize: 16).stream(entry, from: handle, progress: { _ in }, consume: { _ in
                calls += 1
                throw StopError()
            })
        }) { XCTAssertEqual($0 as? StopError, StopError()) }
        XCTAssertEqual(calls, 1)
    }
}

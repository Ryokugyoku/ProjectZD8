import Foundation
import XCTest
@testable import ProjectZD8

/// `ZipEntryInflater` が、CRC・サイズの食い違い・壊れた圧縮データ・上限超えを、止まらずに明示的なエラーで拒否することを検証します。
@MainActor
final class ZipEntryInflaterRejectionTests: XCTestCase {
    /// 展開されるはずの中身です。
    private let content = TestZipSampleData.repetitive(count: 20_000)

    /// 責務: 1ファイルの ZIP を、指定の差し替えで作ります。
    private func zip(_ compression: TestZipEntrySpec.Compression, _ configure: (inout TestZipEntrySpec) -> Void) -> [UInt8] {
        var spec = TestZipEntrySpec.file("a.bin", content, compression)
        configure(&spec)
        return TestZipArchiveBuilder(entries: [spec]).build()
    }

    /// 中央ディレクトリの CRC が違えば `checksumMismatch` です(格納・deflate)。
    func testWrongCRCIsChecksumMismatch() {
        for compression in [TestZipEntrySpec.Compression.stored, .deflate] {
            let bytes = zip(compression) { $0.central.crc = TestZipCRC32.checksum($0.content) ^ 0x0000_0001 }
            TestZipAssertions.assertFails(bytes, with: .checksumMismatch, on: self)
        }
    }

    /// 宣言より短い出力(宣言サイズが実際より大きい)は `sizeMismatch` です。
    func testShorterOutputThanDeclaredIsSizeMismatch() {
        for compression in [TestZipEntrySpec.Compression.stored, .deflate] {
            let bytes = zip(compression) { $0.central.uncompressedSize = UInt32($0.content.count + 5) }
            TestZipAssertions.assertFails(bytes, with: .sizeMismatch, on: self)
        }
    }

    /// 宣言より長い出力(宣言サイズが実際より小さい)は、ZIP のエラーで止まります(宣言を超えて出し続けません)。
    func testLongerOutputThanDeclaredIsRejected() {
        let candidates: [ZipArchiveError] = [.entryTooLarge, .sizeMismatch]
        for compression in [TestZipEntrySpec.Compression.stored, .deflate] {
            let bytes = zip(compression) { $0.central.uncompressedSize = UInt32($0.content.count - 1) }
            TestZipAssertions.assertFails(bytes, withOneOf: candidates, on: self)
        }
    }

    /// 宣言サイズが展開の上限を超えるエントリは `entryTooLarge` です。
    func testDeclaredSizeAboveMaximumIsEntryTooLarge() {
        let bytes = zip(.deflate) { _ in }
        let inflater = ZipEntryInflater(maximumUncompressedSize: 100)
        TestZipAssertions.assertFails(bytes, with: .entryTooLarge, on: self, inflater: inflater)
    }

    /// 宣言サイズが既定の上限(2 GiB)を超える ZIP 爆弾の印は、読み始める前に `entryTooLarge` です。
    func testDeclaredSizeAboveTwoGiBIsEntryTooLarge() {
        let bytes = zip(.deflate) { $0.central.uncompressedSize = 0xC000_0000 }
        TestZipAssertions.assertFails(bytes, with: .entryTooLarge, on: self)
    }

    /// 圧縮データの途中で切れたエントリは、ZIP のエラーで終わります。
    func testDeflateDataCutInTheMiddleFails() {
        let candidates: [ZipArchiveError] = [.inflateFailed, .truncated, .sizeMismatch, .checksumMismatch]
        let random = TestZipSampleData.pseudoRandom(count: 30_000, seed: 5)
        var spec = TestZipEntrySpec.file("a.bin", random)
        spec.keepsCompressedPrefix = 10_000
        TestZipAssertions.assertFails(TestZipArchiveBuilder(entries: [spec]).build(), withOneOf: candidates, on: self)
    }

    /// 圧縮データが実際より短く切られた格納のエントリは、ZIP のエラーで終わります。
    func testStoredDataCutShortFails() {
        let candidates: [ZipArchiveError] = [.truncated, .sizeMismatch, .corruptLocalHeader]
        var spec = TestZipEntrySpec.file("a.bin", content, .stored)
        spec.keepsCompressedPrefix = 100
        TestZipAssertions.assertFails(TestZipArchiveBuilder(entries: [spec]).build(), withOneOf: candidates, on: self)
    }

    /// deflate として不正なデータ(予約された符号の種類)は `inflateFailed` です。
    func testInvalidDeflateStreamIsInflateFailed() {
        let bytes = zip(.deflate) { $0.compressedDataOverride = [UInt8](repeating: 0xFF, count: 64) }
        TestZipAssertions.assertFails(bytes, with: .inflateFailed, on: self)
    }

    /// 擬似乱数の圧縮データ(deflate として無意味)は、ZIP のエラーで終わります。
    func testRandomCompressedBytesFail() {
        let candidates: [ZipArchiveError] = [.inflateFailed, .checksumMismatch, .sizeMismatch, .truncated, .entryTooLarge]
        for seed in UInt64(1)...5 {
            let bytes = zip(.deflate) { $0.compressedDataOverride = TestZipSampleData.pseudoRandom(count: 500, seed: seed) }
            TestZipAssertions.assertFails(bytes, withOneOf: candidates, on: self)
        }
    }
}

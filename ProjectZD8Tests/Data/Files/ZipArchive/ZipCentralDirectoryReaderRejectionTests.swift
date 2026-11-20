import Foundation
import XCTest
@testable import ProjectZD8

/// `ZipCentralDirectoryReader` と展開器が、対応しない・壊れた ZIP を、止まらずに明示的なエラーで拒否することを検証します。
///
/// 暗号化・方式・ZIP64 の拒否は、読み取り器と展開器のどちらが投げてもよいため、全体を読み出して最初のエラーを確かめます。
@MainActor
final class ZipCentralDirectoryReaderRejectionTests: XCTestCase {
    /// 責務: 中身のある1ファイルの ZIP を、指定の差し替えで作ります。
    private func zip(_ configure: (inout TestZipEntrySpec) -> Void) -> [UInt8] {
        var spec = TestZipEntrySpec.file("a.csv", Array("hello,world\r\n".utf8), .stored)
        configure(&spec)
        return TestZipArchiveBuilder(entries: [spec]).build()
    }

    /// 展開後サイズの 0xFFFFFFFF(ZIP64 の印)は拒否します。
    func testZip64MarkerInUncompressedSizeIsRejected() {
        let bytes = zip { $0.central.uncompressedSize = 0xFFFF_FFFF }
        TestZipAssertions.assertFails(bytes, with: .unsupportedZip64, on: self)
    }

    /// 圧縮後サイズの 0xFFFFFFFF(ZIP64 の印)は拒否します。
    func testZip64MarkerInCompressedSizeIsRejected() {
        let bytes = zip { $0.central.compressedSize = 0xFFFF_FFFF }
        TestZipAssertions.assertFails(bytes, with: .unsupportedZip64, on: self)
    }

    /// 局所ヘッダーの位置の 0xFFFFFFFF(ZIP64 の印)は拒否します。
    func testZip64MarkerInLocalHeaderOffsetIsRejected() {
        let bytes = zip { $0.central.localHeaderOffset = 0xFFFF_FFFF }
        TestZipAssertions.assertFails(bytes, with: .unsupportedZip64, on: self)
    }

    /// EOCD の件数 0xFFFF(ZIP64 の印)は拒否します。
    func testZip64MarkerInEntryCountIsRejected() {
        var builder = TestZipArchiveBuilder(entries: [.file("a.csv", [0x41], .stored)])
        builder.endEntryCountOverride = 0xFFFF
        TestZipAssertions.assertFails(builder.build(), with: .unsupportedZip64, on: self)
    }

    /// 暗号化の印(bit0)は拒否します。
    func testEncryptedEntryIsRejected() {
        let bytes = zip {
            $0.central.flags = 0x0001
            $0.local.flags = 0x0001
        }
        TestZipAssertions.assertFails(bytes, with: .encryptedEntry, on: self)
    }

    /// 方式0と8以外(ここでは12)は、方式の値つきで拒否します。
    func testUnsupportedCompressionMethodIsRejectedWithItsValue() {
        let bytes = zip {
            $0.central.method = 12
            $0.local.method = 12
        }
        TestZipAssertions.assertFails(bytes, with: .unsupportedCompressionMethod(12), on: self)
    }

    /// EOCD が無い ZIP は `notZipArchive` です。
    func testMissingEndOfCentralDirectoryIsNotZipArchive() {
        var builder = TestZipArchiveBuilder(entries: [.file("a.csv", [0x41], .stored)])
        builder.omitsEndOfCentralDirectory = true
        TestZipAssertions.assertFails(builder.build(), with: .notZipArchive, on: self)
    }

    /// 空のファイルや EOCD より短いファイルは `notZipArchive` です。
    func testTooShortFilesAreNotZipArchive() {
        TestZipAssertions.assertFails([], with: .notZipArchive, on: self)
        TestZipAssertions.assertFails(Array("PK\u{5}\u{6}".utf8), with: .notZipArchive, on: self)
        TestZipAssertions.assertFails([UInt8](repeating: 0x50, count: 21), with: .notZipArchive, on: self)
    }

    /// ディスク番号が 0 でない(分割 ZIP)は `multiDiskUnsupported` です。
    func testNonZeroDiskNumberIsMultiDiskUnsupported() {
        var builder = TestZipArchiveBuilder(entries: [.file("a.csv", [0x41], .stored)])
        builder.endDiskNumber = 1
        TestZipAssertions.assertFails(builder.build(), with: .multiDiskUnsupported, on: self)
    }

    /// 中央ディレクトリの署名が壊れていれば `corruptCentralDirectory` です。
    func testBrokenCentralDirectorySignatureIsCorrupt() {
        var builder = TestZipArchiveBuilder(entries: [.file("a.csv", [0x41], .stored)])
        builder.corruptsCentralSignature = true
        TestZipAssertions.assertFails(builder.build(), with: .corruptCentralDirectory, on: self)
    }

    /// 局所ヘッダーの署名が壊れていれば `corruptLocalHeader` です。
    func testBrokenLocalHeaderSignatureIsCorrupt() {
        let bytes = zip { $0.corruptsLocalSignature = true }
        TestZipAssertions.assertFails(bytes, with: .corruptLocalHeader, on: self)
    }

    /// 局所ヘッダーの位置がファイルの外なら、ZIP のエラーで終わります。
    func testLocalHeaderOffsetBeyondFileFails() {
        let bytes = zip { $0.central.localHeaderOffset = 0x00FF_FFFF }
        TestZipAssertions.assertFails(
            bytes, withOneOf: [.corruptLocalHeader, .truncated, .corruptCentralDirectory], on: self
        )
    }

    /// 途中で切れた ZIP は、どの長さで切っても(EOCD が欠けるので)ZIP のエラーで終わります。
    func testEveryTruncatedPrefixFailsWithZipError() {
        var spec = TestZipEntrySpec.file("a.csv", TestZipSampleData.repetitive(count: 200))
        spec.usesUTF8Flag = true
        let full = TestZipArchiveBuilder(entries: [.directory("d/"), spec]).build()

        let failures = TestBoundedExecution.run(on: self) {
            (0..<full.count).filter { length in
                guard case .zipError = TestZipExtraction.outcome(of: Array(full.prefix(length))) else { return true }
                return false
            }
        }

        XCTAssertEqual(failures, [], "ZIP のエラーにならなかった切り詰め長")
    }

    /// でたらめなバイト列は、止まらずに ZIP のエラーで終わります。
    func testRandomBytesFailWithZipError() {
        let inputs: [[UInt8]] = [
            TestZipSampleData.pseudoRandom(count: 10_000, seed: 1),
            TestZipSampleData.pseudoRandom(count: 70_000, seed: 2),
            [UInt8](repeating: 0, count: 1_024),
            [UInt8](repeating: 0xFF, count: 1_024)
        ]

        let outcomes = TestBoundedExecution.run(on: self) { inputs.map { TestZipExtraction.outcome(of: $0) } }

        for outcome in outcomes ?? [] {
            guard case .zipError = outcome else { return XCTFail("ZIP のエラーになりませんでした: \(outcome)") }
        }
        XCTAssertEqual(outcomes?.count, inputs.count)
    }

    /// EOCD の署名があっても、中央ディレクトリの位置がファイルの外なら ZIP のエラーで終わります。
    func testEndRecordPointingOutsideFileFails() {
        var writer = TestZipByteWriter()
        writer.append32(0x0605_4B50)
        writer.append16(0)
        writer.append16(0)
        writer.append16(1)
        writer.append16(1)
        writer.append32(46)
        writer.append32(1_000)
        writer.append16(0)

        TestZipAssertions.assertFails(
            writer.bytes, withOneOf: [.corruptCentralDirectory, .truncated, .notZipArchive], on: self
        )
    }
}

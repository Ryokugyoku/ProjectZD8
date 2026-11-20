import Foundation
import XCTest
@testable import ProjectZD8

/// `ZipCentralDirectoryReader` が、正しい ZIP の中央ディレクトリを仕様どおりに読むことを検証します。
@MainActor
final class ZipCentralDirectoryReaderTests: XCTestCase {
    /// 格納と deflate のエントリの、方式・CRC・サイズが中央ディレクトリの値で読めます。
    func testReadsMetadataOfStoredAndDeflatedEntries() throws {
        let stored = Array("stored content".utf8)
        let deflated = TestZipSampleData.repetitive(count: 5_000)
        let zip = TestZipArchiveBuilder(entries: [.file("s.txt", stored, .stored), .file("d.txt", deflated, .deflate)]).build()

        let entries = try TestZipExtraction.entries(in: zip)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].path, "s.txt")
        XCTAssertEqual(entries[0].compressionMethod, 0)
        XCTAssertEqual(entries[0].crc32, TestZipCRC32.checksum(stored))
        XCTAssertEqual(entries[0].compressedSize, UInt64(stored.count))
        XCTAssertEqual(entries[0].uncompressedSize, UInt64(stored.count))
        XCTAssertEqual(entries[1].path, "d.txt")
        XCTAssertEqual(entries[1].compressionMethod, 8)
        XCTAssertEqual(entries[1].crc32, TestZipCRC32.checksum(deflated))
        XCTAssertEqual(entries[1].uncompressedSize, UInt64(deflated.count))
        XCTAssertLessThan(entries[1].compressedSize, entries[1].uncompressedSize)
    }

    /// フォルダのエントリは一覧から除かれ、ファイルだけが残ります(フォルダは飛ばす仕様)。
    func testDirectoryEntriesAreSkippedAndFilesRemain() throws {
        let zip = TestZipArchiveBuilder(entries: [.directory("typeD_x/"), .file("typeD_x/a.csv", [0x41])]).build()

        let entries = try TestZipExtraction.entries(in: zip)

        XCTAssertEqual(entries.compactMap(\.path), ["typeD_x/a.csv"])
        XCTAssertEqual(entries.map(\.isDirectory), [false])
    }

    /// UTF-8 の印がある漢字の名前を読めます。
    func testUTF8FlaggedKanjiNameIsReadAsPath() throws {
        var spec = TestZipEntrySpec.file("typeD_okinawa/沖縄県警_202609_k_2.1.csv", [0x41])
        spec.usesUTF8Flag = true

        let entries = try TestZipExtraction.entries(in: TestZipArchiveBuilder(entries: [spec]).build())

        XCTAssertEqual(entries.first?.path, "typeD_okinawa/沖縄県警_202609_k_2.1.csv")
        XCTAssertEqual(entries.first?.flags, 0x0800)
    }

    /// UTF-8 の印が無い非 ASCII の名前は `path` が `nil` で、バイト列は残ります。
    func testNonASCIINameWithoutUTF8FlagHasNilPathButKeepsBytes() throws {
        var spec = TestZipEntrySpec.file("x", [0x41])
        spec.rawNameBytes = [0x95, 0x5C, 0x2E, 0x63, 0x73, 0x76]

        let entries = try TestZipExtraction.entries(in: TestZipArchiveBuilder(entries: [spec]).build())

        XCTAssertNil(entries.first?.path)
        XCTAssertEqual(entries.first?.pathBytes, [0x95, 0x5C, 0x2E, 0x63, 0x73, 0x76])
    }

    /// エントリが無い ZIP(EOCD だけ)は、空の一覧になります。
    func testArchiveWithoutEntriesHasEmptyList() throws {
        let zip = TestZipArchiveBuilder(entries: []).build()

        XCTAssertEqual(zip.count, 22)
        XCTAssertEqual(try TestZipExtraction.entries(in: zip).count, 0)
    }

    /// 末尾にコメントが付いていても読めます(0 B・短い・最大の 65,535 B)。
    func testTrailingCommentDoesNotHideEntries() throws {
        for length in [0, 7, 100, 65_535] {
            var builder = TestZipArchiveBuilder(entries: [.file("a.txt", Array("abc".utf8)), .file("b.txt", [])])
            builder.trailingComment = TestZipSampleData.repetitive(count: length).map { $0 == 0x50 ? 0x51 : $0 }

            let entries = try TestZipExtraction.entries(in: builder.build())

            XCTAssertEqual(entries.compactMap(\.path), ["a.txt", "b.txt"], "コメント長 \(length)")
        }
    }

    /// bit3 が立ち、局所ヘッダーの CRC とサイズが 0 でも、中央ディレクトリの値で読めます。
    func testDataDescriptorEntryReportsCentralValues() throws {
        let content = Array("descriptor content".utf8)
        var spec = TestZipEntrySpec.file("dd.txt", content)
        spec.usesDataDescriptor = true

        let entries = try TestZipExtraction.entries(in: TestZipArchiveBuilder(entries: [spec]).build())

        XCTAssertEqual(entries.first?.flags, 0x0008)
        XCTAssertEqual(entries.first?.crc32, TestZipCRC32.checksum(content))
        XCTAssertEqual(entries.first?.uncompressedSize, UInt64(content.count))
        XCTAssertGreaterThan(entries.first?.compressedSize ?? 0, 0)
    }

    /// 局所ヘッダーの位置が、先頭のエントリは 0、次のエントリは先頭の記録の後ろです。
    func testLocalHeaderOffsetsFollowTheEntryLayout() throws {
        let first = Array("first".utf8)
        let zip = TestZipArchiveBuilder(entries: [.file("a", first, .stored), .file("b", [0x42], .stored)]).build()

        let entries = try TestZipExtraction.entries(in: zip)

        XCTAssertEqual(entries[0].localHeaderOffset, 0)
        XCTAssertEqual(entries[1].localHeaderOffset, UInt64(30 + 1 + first.count))
    }
}

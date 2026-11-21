import Foundation
import XCTest
@testable import ProjectZD8

/// `ZipArchiveEntry` の判定(フォルダ・暗号化・名前の読み方)を、仕様どおりに検証します。
@MainActor
final class ZipArchiveEntryTests: XCTestCase {
    /// 責務: 指定の名前とフラグだけを変えたエントリを作ります。
    private func entry(_ name: [UInt8], flags: UInt16 = 0) -> ZipArchiveEntry {
        ZipArchiveEntry(
            pathBytes: name, flags: flags, compressionMethod: 0, crc32: 0,
            compressedSize: 0, uncompressedSize: 0, localHeaderOffset: 0
        )
    }

    /// 名前が `/` で終わるものだけがフォルダです。
    func testIsDirectoryOnlyWhenNameEndsWithSlash() {
        XCTAssertTrue(entry(Array("typeD/".utf8)).isDirectory)
        XCTAssertFalse(entry(Array("typeD/a.csv".utf8)).isDirectory)
        XCTAssertFalse(entry(Array("a/b".utf8)).isDirectory)
    }

    /// bit0 が立っている時だけ暗号化です(他のビットは影響しません)。
    func testIsEncryptedOnlyWhenBitZeroIsSet() {
        XCTAssertTrue(entry([0x61], flags: 0x0001).isEncrypted)
        XCTAssertTrue(entry([0x61], flags: 0x0809).isEncrypted)
        XCTAssertFalse(entry([0x61], flags: 0x0800).isEncrypted)
        XCTAssertFalse(entry([0x61], flags: 0x0008).isEncrypted)
        XCTAssertFalse(entry([0x61], flags: 0).isEncrypted)
    }

    /// フラグ 0x800 が立っていれば、名前を UTF-8 として読みます。
    func testPathReadsUTF8WhenFlagIsSet() {
        let name = Array("沖縄県警_202609_k_2.1.csv".utf8)
        XCTAssertEqual(entry(name, flags: 0x0800).path, "沖縄県警_202609_k_2.1.csv")
    }

    /// フラグが無い時は、ASCII として読めた時だけ名前を返し、それ以外は `nil` です。
    func testPathWithoutUTF8FlagIsReadOnlyForASCII() {
        XCTAssertEqual(entry(Array("a/b.csv".utf8)).path, "a/b.csv")
        XCTAssertNil(entry(Array("沖縄".utf8)).path)
        XCTAssertNil(entry([0x61, 0x80]).path)
    }

    /// フラグがあっても UTF-8 として不正なバイト列なら `nil` です(誤った名前を作りません)。
    func testPathIsNilForInvalidUTF8EvenWithFlag() {
        XCTAssertNil(entry([0xFF, 0xFE], flags: 0x0800).path)
    }
}

import Foundation
import XCTest
@testable import ProjectZD8

/// `CRC32Checksum` が、標準の CRC32(IEEE 802.3)を、分割して与えても同じ値で返すことを検証します。
@MainActor
final class CRC32ChecksumTests: XCTestCase {
    /// 責務: バイト列を、指定の大きさに区切って `update` へ渡した結果を返します。
    private func checksum(of bytes: [UInt8], chunkSize: Int) -> UInt32 {
        var crc = CRC32Checksum()
        var start = 0
        while start < bytes.count {
            let end = min(start + chunkSize, bytes.count)
            bytes[start..<end].withUnsafeBytes { crc.update($0) }
            start = end
        }
        return crc.value
    }

    /// 何も与えない時の値は 0 です。
    func testEmptyInputIsZero() {
        XCTAssertEqual(CRC32Checksum().value, 0)
        XCTAssertEqual(checksum(of: [], chunkSize: 4), 0)
    }

    /// 標準のテストベクトル "123456789" は 0xCBF43926 です。
    func testStandardCheckValue() {
        XCTAssertEqual(checksum(of: Array("123456789".utf8), chunkSize: 100), 0xCBF4_3926)
    }

    /// 既知の値(CRC32 の公開されたテストベクトル)に一致します。
    func testKnownVectors() {
        XCTAssertEqual(checksum(of: Array("a".utf8), chunkSize: 1), 0xE8B7_BE43)
        XCTAssertEqual(checksum(of: Array("The quick brown fox jumps over the lazy dog".utf8), chunkSize: 100), 0x414F_A339)
        XCTAssertEqual(checksum(of: [0x00], chunkSize: 1), 0xD202_EF8D)
        XCTAssertEqual(checksum(of: [UInt8](repeating: 0, count: 32), chunkSize: 32), 0x190A_55AD)
    }

    /// 分割の仕方(1 B / 7 B / 一括)に値が依存しません。
    func testChunkingDoesNotChangeValue() {
        let bytes = TestZipSampleData.pseudoRandom(count: 5_000, seed: 11)
        let whole = checksum(of: bytes, chunkSize: bytes.count)
        XCTAssertEqual(checksum(of: bytes, chunkSize: 1), whole)
        XCTAssertEqual(checksum(of: bytes, chunkSize: 7), whole)
        XCTAssertEqual(checksum(of: bytes, chunkSize: 4_093), whole)
    }

    /// テスト側の独立実装と、乱数・繰り返し・数 MB のデータで一致します。
    func testMatchesIndependentImplementation() {
        let inputs: [[UInt8]] = [
            TestZipSampleData.pseudoRandom(count: 1_000, seed: 21),
            TestZipSampleData.repetitive(count: 100_000),
            TestZipSampleData.pseudoRandom(count: 1_000_000, seed: 22)
        ]
        for bytes in inputs {
            XCTAssertEqual(checksum(of: bytes, chunkSize: 65_536), TestZipCRC32.checksum(bytes), "\(bytes.count) B")
        }
    }

    /// 0 バイトを挟んで `update` しても値は変わりません。
    func testEmptyUpdateDoesNotChangeValue() {
        var crc = CRC32Checksum()
        Array("123456789".utf8).withUnsafeBytes { crc.update($0) }
        let before = crc.value
        [UInt8]().withUnsafeBytes { crc.update($0) }
        XCTAssertEqual(crc.value, before)
    }
}

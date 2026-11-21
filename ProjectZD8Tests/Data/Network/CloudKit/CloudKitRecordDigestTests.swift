import CryptoKit
import Foundation
import XCTest
@testable import ProjectZD8

/// `CloudKitRecordDigest` が SHA-256 の16進と、アカウントの fingerprint を仕様どおりに返すことを検証します。
///
/// 仕様: `sha256Hex` は小文字16進64文字。`accountFingerprint` は識別子の UTF-8 の SHA-256 に等しい。
final class CloudKitRecordDigestTests: XCTestCase {
    /// 既知の入力 "abc" の SHA-256 が公開されている値と一致することを検証します。
    ///
    /// 責務: 決まった入力に対する固定の期待値を確認します。
    func testSha256HexOfAbcMatchesPublishedVector() {
        XCTAssertEqual(
            CloudKitRecordDigest.sha256Hex(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    /// 空のデータの SHA-256 が公開されている値と一致することを検証します。
    ///
    /// 責務: 境界値(空入力)を確認します。
    func testSha256HexOfEmptyDataMatchesPublishedVector() {
        XCTAssertEqual(
            CloudKitRecordDigest.sha256Hex(Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    /// 出力が小文字16進の64文字であることを検証します。
    ///
    /// 責務: 長さと文字種を確認します。
    func testSha256HexIsLowercaseHexOf64Characters() {
        let digest = CloudKitRecordDigest.sha256Hex(Data([0xFF, 0x00, 0xAB]))
        XCTAssertEqual(digest.count, 64)
        XCTAssertEqual(digest, digest.lowercased())
        XCTAssertTrue(digest.allSatisfy { $0.isHexDigit })
    }

    /// 入力が1バイト違えば出力も違うことを検証します。
    ///
    /// 責務: 異なる入力が異なる digest になることを確認します。
    func testSha256HexDiffersForDifferentInputs() {
        XCTAssertNotEqual(
            CloudKitRecordDigest.sha256Hex(Data([1, 2, 3])),
            CloudKitRecordDigest.sha256Hex(Data([1, 2, 4]))
        )
    }

    /// fingerprint が識別子の UTF-8 の SHA-256 と等しいことを検証します。
    ///
    /// 責務: 既存の各ストアと同じ算出方法であることを、独立の実装(CryptoKit)で確認します。
    func testAccountFingerprintEqualsSha256OfUTF8() {
        let identifier = "000123.abcdef.4567"
        let expected = SHA256.hash(data: Data(identifier.utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(CloudKitRecordDigest.accountFingerprint(for: identifier), expected)
    }

    /// 非 ASCII の識別子でも UTF-8 のバイト列で算出されることを検証します。
    ///
    /// 責務: 多バイト文字の扱いを確認します。
    func testAccountFingerprintUsesUTF8ForNonASCII() {
        XCTAssertEqual(
            CloudKitRecordDigest.accountFingerprint(for: "あ"),
            CloudKitRecordDigest.sha256Hex(Data("あ".utf8))
        )
    }

    /// 同じ識別子は同じ fingerprint、別の識別子は別の fingerprint になることを検証します。
    ///
    /// 責務: 決定性と識別性を確認します。
    func testAccountFingerprintIsDeterministicAndDistinct() {
        XCTAssertEqual(
            CloudKitRecordDigest.accountFingerprint(for: "a"),
            CloudKitRecordDigest.accountFingerprint(for: "a")
        )
        XCTAssertNotEqual(
            CloudKitRecordDigest.accountFingerprint(for: "a"),
            CloudKitRecordDigest.accountFingerprint(for: "b")
        )
    }
}

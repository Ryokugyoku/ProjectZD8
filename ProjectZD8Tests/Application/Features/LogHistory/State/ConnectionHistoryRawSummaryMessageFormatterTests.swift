import Foundation
import XCTest
@testable import ProjectZD8

/// Raw件数と容量を含む alert 本文の整形を検証します。
@MainActor
final class ConnectionHistoryRawSummaryMessageFormatterTests: XCTestCase {
    /// 書式キー、件数、容量を書式へ埋め込みます。
    ///
    /// 責務: 注入したローカライズ解決と容量表記で本文を組み立てることを確認します。
    func testTextEmbedsCountAndBytesIntoResolvedFormat() {
        var requestedKeys: [String] = []
        var requestedBytes: [Int64] = []
        let formatter = ConnectionHistoryRawSummaryMessageFormatter(
            localizedFormat: { key in
                requestedKeys.append(key)
                return "%lld records (%@)"
            },
            byteCountText: { bytes in
                requestedBytes.append(bytes)
                return "\(bytes) B"
            },
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertEqual(formatter.text(formatKey: "format.key", recordCount: 12, byteCount: 2_048), "12 records (2048 B)")
        XCTAssertEqual(requestedKeys, ["format.key"])
        XCTAssertEqual(requestedBytes, [2_048])
    }

    /// 負のバイト数は0として容量表記へ渡します。
    ///
    /// 責務: 負値、0、正値の境界で容量表記へ渡す値を確認します。
    func testNegativeByteCountIsClampedToZero() {
        var requestedBytes: [Int64] = []
        let formatter = ConnectionHistoryRawSummaryMessageFormatter(
            localizedFormat: { _ in "%lld/%@" },
            byteCountText: { bytes in
                requestedBytes.append(bytes)
                return "\(bytes)"
            }
        )

        XCTAssertEqual(formatter.text(formatKey: "k", recordCount: 1, byteCount: -1), "1/0")
        XCTAssertEqual(formatter.text(formatKey: "k", recordCount: 1, byteCount: 0), "1/0")
        XCTAssertEqual(formatter.text(formatKey: "k", recordCount: 1, byteCount: 1), "1/1")
        XCTAssertEqual(requestedBytes, [0, 0, 1])
    }

    /// 既定の変換器は String Catalog と `ByteCountFormatter` の `.file` 表記を使います。
    ///
    /// 責務: 既定値が従来の View と同じ文字列を返すことを確認します。
    func testDefaultFormatterMatchesLegacyViewComposition() {
        let formatter = ConnectionHistoryRawSummaryMessageFormatter()
        let keys = ["history.raw.remove.safe.message", "history.raw.remove.warning.message", "history.delete.warning.message"]

        for key in keys {
            let format = String(localized: String.LocalizationValue(key))
            let bytes = ByteCountFormatter.string(fromByteCount: 4_096, countStyle: .file)
            let expected = String(format: format, locale: .autoupdatingCurrent, Int64(7), bytes)

            XCTAssertEqual(formatter.text(formatKey: key, recordCount: 7, byteCount: 4_096), expected, key)
            XCTAssertNotEqual(format, key, "String Catalog に \(key) が登録されていること")
        }
        XCTAssertEqual(formatter.locale, .autoupdatingCurrent)
    }
}

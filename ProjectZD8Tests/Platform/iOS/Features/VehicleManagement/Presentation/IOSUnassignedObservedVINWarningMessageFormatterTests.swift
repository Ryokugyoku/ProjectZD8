#if os(iOS)
import Foundation
import XCTest
@testable import ProjectZD8

/// 未登録車両の警告本文の整形 `IOSUnassignedObservedVINWarningMessageFormatter` を検証します。
@MainActor
final class IOSUnassignedObservedVINWarningMessageFormatterTests: XCTestCase {
    /// 数字の書式を固定するロケールです。
    private let locale = Locale(identifier: "en_US_POSIX")

    /// 警告なしは本文を返しません。
    ///
    /// 責務: `.hidden` で `nil` になることを確認します。
    func testHiddenWarningHasNoMessage() {
        XCTAssertNil(IOSUnassignedObservedVINWarningMessageFormatter.message(for: .hidden, locale: locale))
    }

    /// 失敗の本文は書式指定子もキーも残さない文章です。
    ///
    /// 責務: `.loadFailed` の本文が空でなく、キーそのものや `%` を含まないことを確認します。
    func testLoadFailedMessageIsLocalizedText() throws {
        let message = try XCTUnwrap(IOSUnassignedObservedVINWarningMessageFormatter.message(for: .loadFailed, locale: locale))
        XCTAssertFalse(message.isEmpty)
        XCTAssertNotEqual(message, UnassignedObservedVINWarning.loadFailed.messageKey)
        XCTAssertFalse(message.contains("%"))
    }

    /// 未登録警告の本文には車両数とログ件数の両方が埋め込まれます。
    ///
    /// 責務: 3台7件の警告の本文に「3」と「7」が入り、書式指定子が残らないことを確認します。
    func testUnregisteredMessageEmbedsBothCounts() throws {
        let vins = ["A", "B", "C", "A", "B", "C", "A"]
        let sessions = vins.enumerated().map { index, suffix in
            UnassignedObservedVINSessionFixture.session(vin: "JF1ZD8A11P900000\(suffix)", startedAt: Double(index))
        }
        let warning = UnassignedObservedVINWarning(sessions: sessions)
        let message = try XCTUnwrap(IOSUnassignedObservedVINWarningMessageFormatter.message(for: warning, locale: locale))
        XCTAssertTrue(message.contains("3"), message)
        XCTAssertTrue(message.contains("7"), message)
        XCTAssertFalse(message.contains("%"), message)
    }

    /// 1台1件の本文にも件数が入り、書式指定子が残りません。
    ///
    /// 責務: 最小の未登録警告でも整形が書式を埋め切ることを確認します。
    func testSingleVehicleSingleLogMessageIsFormatted() throws {
        let warning = UnassignedObservedVINWarning(sessions: [UnassignedObservedVINSessionFixture.session(vin: "JF1ZD8A11P9000001", startedAt: 1)])
        let message = try XCTUnwrap(IOSUnassignedObservedVINWarningMessageFormatter.message(for: warning, locale: locale))
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(message.contains("%"), message)
    }
}
#endif

import Foundation
import XCTest
@testable import ProjectZD8

/// 走行ルート(`history.route.*`)の文言キーが、すべて `Localizable.xcstrings` にあり ja / en / es で訳されていることを検証します。
@MainActor
final class DrivingRouteLocalizationTests: XCTestCase {
    private let textKeys = DrivingRouteTextKeys()

    /// 設計書 §6 の、画面と要約が使う固定のキーです(型に static のキーが無いため一覧で持ちます)。
    private static let fixedKeys = [
        "history.route.title", "history.route.loading", "history.route.loading.cloud", "history.route.expand",
        "history.route.close", "history.route.retry", "history.route.marker.start", "history.route.marker.end",
        "history.route.map.accessibility", "history.route.summary.length", "history.route.summary.recorded_duration",
        "history.route.summary.coverage"
    ]

    /// 記録中以外の事象に由来する、部分の注記を持つ理由(設計書 §6 の `notice.partial.*` の7つ)です。
    private static let partialReasons: [DrivingRouteAbsenceReason] = [
        .disabledBySetting, .authorizationRestricted, .authorizationDenied, .authorizationNotDetermined,
        .backgroundWithoutAlwaysAuthorization, .locationUnavailable, .unsupportedPlatform
    ]

    /// 責務: 全理由の「描けない」文言キーを `DrivingRouteTextKeys` から作ります。
    private func absenceKeys() -> [String] {
        DrivingRouteAbsenceReason.allCases.map { textKeys.absence($0).messageKey }
    }

    /// 責務: 全種の注記(部分は7つの理由)の文言キーを `DrivingRouteTextKeys` から作ります。
    private func noticeKeys() -> [String] {
        let partial = Self.partialReasons.map { textKeys.notice(.partiallyRecorded($0)) }
        let others = [DrivingRouteNotice.reducedAccuracy, .inaccurateFixesExcluded, .unverifiedRestoredCopy].map(textKeys.notice)
        return partial + others
    }

    /// 責務: 失敗の分類が返す文言キー(更新が必要・一般の失敗)を作ります。
    private func failureKeys() -> [String] {
        let classifier = DrivingRouteFailureClassifier()
        let update = classifier.failure(for: ConnectionSessionLocationTrackCloudError.unsupportedPayloadFormat(version: 99))
        let general = classifier.failure(for: URLError(.notConnectedToInternet))
        return [update.messageKey, general.messageKey]
    }

    /// 描けない理由11種の文言キーが、重複なくカタログにあります。
    ///
    /// 責務: `DrivingRouteAbsenceReason.allCases` から作ったキーを確認します。
    func testAbsenceKeysAreTranslated() throws {
        let keys = absenceKeys()
        let catalog = try LocalizableCatalogChecker()
        catalog.assertDistinct(keys, expectedCount: 11)
        catalog.assertAll(keys)
        XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("history.route.absence.") })
    }

    /// 理由ごとの記号の名前が空でありません。
    ///
    /// 責務: 全理由の `systemImage` が空白だけでないことを確認します。
    func testAbsenceSymbolsAreNotEmpty() {
        for reason in DrivingRouteAbsenceReason.allCases {
            let symbol = textKeys.absence(reason).systemImage.trimmingCharacters(in: .whitespaces)
            XCTAssertFalse(symbol.isEmpty, "\(reason)")
        }
    }

    /// 注記の文言キーが、カタログにあります。
    ///
    /// 責務: 部分の注記7種と、粗い位置・精度の低い点・復元の写しの注記を確認します。
    func testNoticeKeysAreTranslated() throws {
        let keys = noticeKeys()
        let catalog = try LocalizableCatalogChecker()
        catalog.assertDistinct(keys, expectedCount: 10)
        catalog.assertAll(keys)
    }

    /// 失敗の分類が返す2つのキーが、カタログにあります。
    ///
    /// 責務: 更新が必要(再試行なし)と一般の失敗(再試行あり)のキーを確認します。
    func testFailureKeysAreTranslated() throws {
        let keys = failureKeys()
        XCTAssertEqual(keys, ["history.route.failure.update_required", "history.route.failure.load"])
        try LocalizableCatalogChecker().assertAll(keys)
    }

    /// 画面と要約の固定のキーが、カタログにあります。
    ///
    /// 責務: 設計書 §6 の固定の12キーを確認します。
    func testFixedKeysAreTranslated() throws {
        let catalog = try LocalizableCatalogChecker()
        catalog.assertDistinct(Self.fixedKeys, expectedCount: 12)
        catalog.assertAll(Self.fixedKeys)
    }

    /// カタログの `history.route.` のキーが、すべて訳されています。
    ///
    /// 責務: 製品コードが使わないキーも含め、カタログ側から数えて訳の欠落・書式指定子の不一致を確認します。
    func testEveryCatalogRouteKeyIsTranslated() throws {
        let catalog = try LocalizableCatalogChecker()
        let keys = catalog.catalogKeys(prefix: "history.route.")
        XCTAssertFalse(keys.isEmpty, "history.route.* のキーがカタログに無い")
        catalog.assertAll(keys)
    }

    /// 製品コードが返すキーを、カタログの `history.route.` のキーが覆っています。
    ///
    /// 責務: 理由・注記・失敗・固定のキーがすべてカタログの一覧に含まれることを確認します。
    func testCatalogCoversEveryProducedKey() throws {
        let catalog = Set(try LocalizableCatalogChecker().catalogKeys(prefix: "history.route."))
        let produced = absenceKeys() + noticeKeys() + failureKeys() + Self.fixedKeys
        XCTAssertTrue(Set(produced).isSubset(of: catalog), "カタログに無い: \(Set(produced).subtracting(catalog).sorted())")
    }
}

import Foundation
import XCTest
@testable import ProjectZD8

/// 走行ルートの理由・注記から文言キーへの対応を、設計書 §6 のキーの文字列で検証します。
@MainActor
final class DrivingRouteTextKeysTests: XCTestCase {
    /// 検証対象です。
    private let textKeys = DrivingRouteTextKeys()

    /// 理由ごとの期待するキーです(設計書 §6 の `absence.*`)。
    private let expectedAbsenceKeys: [(DrivingRouteAbsenceReason, String)] = [
        (.unsupportedPlatform, "history.route.absence.unsupported_platform"),
        (.disabledBySetting, "history.route.absence.disabled_by_setting"),
        (.authorizationRestricted, "history.route.absence.authorization_restricted"),
        (.authorizationDenied, "history.route.absence.authorization_denied"),
        (.authorizationNotDetermined, "history.route.absence.authorization_not_determined"),
        (.backgroundWithoutAlwaysAuthorization, "history.route.absence.background_without_always"),
        (.locationUnavailable, "history.route.absence.location_unavailable"),
        (.noFixesReceived, "history.route.absence.no_fixes_received"),
        (.allFixesInaccurate, "history.route.absence.all_fixes_inaccurate"),
        (.notRecorded, "history.route.absence.not_recorded"),
        (.notInCloud, "history.route.absence.not_in_cloud"),
    ]

    /// 注記ごとの期待するキーです(設計書 §6 の `notice.*`。partial は事象由来の7つの理由)。
    private let expectedNoticeKeys: [(DrivingRouteNotice, String)] = [
        (.partiallyRecorded(.unsupportedPlatform), "history.route.notice.partial.unsupported_platform"),
        (.partiallyRecorded(.disabledBySetting), "history.route.notice.partial.disabled_by_setting"),
        (.partiallyRecorded(.authorizationRestricted), "history.route.notice.partial.authorization_restricted"),
        (.partiallyRecorded(.authorizationDenied), "history.route.notice.partial.authorization_denied"),
        (.partiallyRecorded(.authorizationNotDetermined), "history.route.notice.partial.authorization_not_determined"),
        (.partiallyRecorded(.backgroundWithoutAlwaysAuthorization), "history.route.notice.partial.background_without_always"),
        (.partiallyRecorded(.locationUnavailable), "history.route.notice.partial.location_unavailable"),
        (.reducedAccuracy, "history.route.notice.reduced_accuracy"),
        (.inaccurateFixesExcluded, "history.route.notice.inaccurate_excluded"),
        (.unverifiedRestoredCopy, "history.route.notice.unverified_restore"),
    ]

    /// 全ての理由が設計書 §6 のキーになります。
    ///
    /// 責務: 11種の理由それぞれのキーの文字列を直接比べます。
    func testEachAbsenceReasonMapsToDesignedKey() {
        XCTAssertEqual(expectedAbsenceKeys.count, DrivingRouteAbsenceReason.allCases.count, "期待値の表が全ての理由を覆っていません")
        for (reason, key) in expectedAbsenceKeys {
            XCTAssertEqual(textKeys.absence(reason).messageKey, key, "\(reason)")
        }
    }

    /// 全ての理由に、空でない記号名が付きます。
    ///
    /// 責務: 表示する SF Symbols の名前が空にならないことを確認します。
    func testEachAbsenceReasonHasNonEmptySystemImage() {
        for reason in DrivingRouteAbsenceReason.allCases {
            XCTAssertFalse(textKeys.absence(reason).systemImage.isEmpty, "\(reason)")
        }
    }

    /// 全ての注記が設計書 §6 のキーになります。
    ///
    /// 責務: partial の7種と、概略・除外・未確認の復元のキーの文字列を直接比べます。
    func testEachNoticeMapsToDesignedKey() {
        for (notice, key) in expectedNoticeKeys {
            XCTAssertEqual(textKeys.notice(notice), key, "\(notice)")
        }
    }

    /// 理由のキーも注記のキーも空でなく、互いに重ならず、`history.route.` で始まります。
    ///
    /// 責務: 理由11種と注記10種の全てのキーの一意性と接頭辞を確認します。
    func testAllKeysAreNonEmptyUniqueAndPrefixed() {
        let absenceKeys = DrivingRouteAbsenceReason.allCases.map { textKeys.absence($0).messageKey }
        let noticeKeys = expectedNoticeKeys.map { textKeys.notice($0.0) }
        let allKeys = absenceKeys + noticeKeys

        XCTAssertEqual(Set(allKeys).count, allKeys.count, "キーが重複しています: \(allKeys)")
        for key in allKeys {
            XCTAssertFalse(key.isEmpty)
            XCTAssertTrue(key.hasPrefix("history.route."), key)
        }
    }
}

import XCTest
@testable import ProjectZD8

/// 初回の選択画面の表示条件 `AutomaticRecordingChoicePromptPolicy` を検証します。
@MainActor
final class AutomaticRecordingChoicePromptPolicyTests: XCTestCase {
    /// サインイン済みかつ未表示の端末では表示します。
    ///
    /// 責務: 表示条件が真になる唯一の組合せを確認します。
    func testPresentsWhenSignedInAndNotCompleted() {
        XCTAssertTrue(AutomaticRecordingChoicePromptPolicy.shouldPresent(isSignedIn: true, isPromptCompleted: false))
    }

    /// 表示済みの端末ではサインイン済みでも表示しません。
    ///
    /// 責務: サインイン済み・表示済みの組合せが偽になることを確認します。
    func testDoesNotPresentWhenAlreadyCompleted() {
        XCTAssertFalse(AutomaticRecordingChoicePromptPolicy.shouldPresent(isSignedIn: true, isPromptCompleted: true))
    }

    /// 未サインインでは未表示の端末でも表示しません。
    ///
    /// 責務: 未サインイン・未表示の組合せが偽になることを確認します。
    func testDoesNotPresentWhenSignedOut() {
        XCTAssertFalse(AutomaticRecordingChoicePromptPolicy.shouldPresent(isSignedIn: false, isPromptCompleted: false))
    }

    /// 未サインインかつ表示済みでは表示しません。
    ///
    /// 責務: 両条件とも満たさない組合せが偽になることを確認します。
    func testDoesNotPresentWhenSignedOutAndCompleted() {
        XCTAssertFalse(AutomaticRecordingChoicePromptPolicy.shouldPresent(isSignedIn: false, isPromptCompleted: true))
    }
}

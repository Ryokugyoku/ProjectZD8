import XCTest
@testable import ProjectZD8

/// `AuthenticationPhase.showsAuthenticatedShell` が、認証済み画面を出す段階だけ true になることを検証します。
///
/// 仕様: `.signedIn` と `.deletingAccount`(削除の進行画面を出し続ける)では true、それ以外は false。
final class AuthenticationPhaseTests: XCTestCase {
    /// 全ての段階について、認証済み画面を出すかどうかを検証します。
    ///
    /// 責務: 5段階それぞれの期待値を確認します。
    func testShowsAuthenticatedShellForEveryPhase() {
        let expectations: [(AuthenticationPhase, Bool)] = [
            (.checkingSession, false),
            (.signedOut, false),
            (.signingIn, false),
            (.signedIn, true),
            (.deletingAccount, true)
        ]
        for (phase, expected) in expectations {
            XCTAssertEqual(phase.showsAuthenticatedShell, expected, "\(phase)")
        }
    }
}

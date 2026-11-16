import XCTest
@testable import ProjectZD8

/// 認証段階の変化で取得を終わらせる理由が、サインアウトの時だけ `accountSignedOut` になることを検証します。
///
/// 仕様: U8 R1(サインアウトによる停止は、どの経路の記録でも `accountSignedOut`)。
final class AuthenticationAcquisitionEndPolicyTests: XCTestCase {
    /// サインアウトへの変化では、`accountSignedOut` で終わらせます(ユーザー切断ではありません)。
    ///
    /// 責務: `.signedOut` の理由が `.accountSignedOut` であることを確認します。
    func testSignedOutEndsWithAccountSignedOut() {
        XCTAssertEqual(AuthenticationAcquisitionEndPolicy().endReason(forChangeTo: .signedOut), .accountSignedOut)
    }

    /// 確認中・サインイン中・サインイン済みへの変化では、取得を終わらせません。
    ///
    /// 責務: サインアウト以外の3段階で `nil` を返すことを確認します。
    func testOtherPhasesDoNotEndAcquisition() {
        let phases: [AuthenticationPhase] = [.checkingSession, .signingIn, .signedIn]
        for phase in phases {
            XCTAssertNil(AuthenticationAcquisitionEndPolicy().endReason(forChangeTo: phase), "\(phase)")
        }
    }
}

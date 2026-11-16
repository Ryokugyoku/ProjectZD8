import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionAuthenticationRelay` が認証状態から監視・記録側へ伝える内容を、段階と識別子の変化ごとに検証します。
///
/// 仕様: U5 受け入れ条件 16・17(B4。確認できていない資格はサインアウトとして扱う。Driver の判定は従来どおり)。
final class AdapterLinkSupervisionAuthenticationRelayTests: XCTestCase {
    /// 指示の型です。
    private typealias Instruction = AdapterLinkSupervisionAuthenticationRelay.Instruction
    /// 識別子の変化の型です。
    private typealias Change = AdapterLinkSupervisionAuthenticationRelay.AccountIdentifierChange

    /// 指示を作ります。
    ///
    /// 責務: 期待値を短く書くための組み立てです。
    private func instruction(account: Change? = nil, signedIn: Bool? = nil, reloads: Bool = false) -> Instruction {
        Instruction(accountIdentifierChange: account, isSignedIn: signedIn, reloadsDefaultAdapterPreference: reloads)
    }

    /// 最初の反映は、段階が何であってもサインイン有無を伝えます。確認中は識別子を伝えません。
    ///
    /// 責務: 起動時の確認中で、識別子の変化なし・サインインなし・読み直しなしになることを確認します。
    func testFirstCheckingSessionReportsNotSignedIn() {
        var relay = AdapterLinkSupervisionAuthenticationRelay()
        XCTAssertEqual(relay.apply(phase: .checkingSession, userIdentifier: nil), instruction(signedIn: false))
    }

    /// サインイン済みになると、識別子とサインイン済みを伝え、同じ状態の繰り返しでは何も伝えません。
    ///
    /// 責務: サインイン済みの初回と2回目の指示を確認します。
    func testSignedInReportsIdentifierOnce() {
        var relay = AdapterLinkSupervisionAuthenticationRelay()
        _ = relay.apply(phase: .checkingSession, userIdentifier: nil)
        XCTAssertEqual(relay.apply(phase: .signedIn, userIdentifier: "u1"), instruction(account: Change(accountIdentifier: "u1"), signedIn: true))
        XCTAssertEqual(relay.apply(phase: .signedIn, userIdentifier: "u1"), instruction())
    }

    /// サインアウト(確認できなかった場合を含む)になると、識別子を外し、サインインなしと既定アダプター設定の読み直しを伝えます。
    ///
    /// 責務: サインイン済みからのサインアウトと、その繰り返しの指示を確認します。
    func testSignedOutClearsIdentifierAndReloadsPreference() {
        var relay = AdapterLinkSupervisionAuthenticationRelay()
        _ = relay.apply(phase: .signedIn, userIdentifier: "u1")
        XCTAssertEqual(
            relay.apply(phase: .signedOut, userIdentifier: nil),
            instruction(account: Change(accountIdentifier: nil), signedIn: false, reloads: true)
        )
        XCTAssertEqual(relay.apply(phase: .signedOut, userIdentifier: nil), instruction())
    }

    /// 起動時の確認ができずにサインアウトした場合(識別子をまだ伝えていない)は、識別子の変化は伝えず、サインインなしと読み直しを伝えます。
    ///
    /// 責務: 確認中 → サインアウトで、保存済み識別子を暫定的に伝えないことを確認します(受け入れ条件 16)。
    func testUnconfirmedCheckDoesNotReportIdentifier() {
        var relay = AdapterLinkSupervisionAuthenticationRelay()
        _ = relay.apply(phase: .checkingSession, userIdentifier: nil)
        XCTAssertEqual(relay.apply(phase: .signedOut, userIdentifier: nil), instruction(signedIn: false, reloads: true))
    }

    /// サインイン中・確認中へ移っても識別子は前のまま保ち、サインインなしだけを伝えます。
    ///
    /// 責務: サインイン済み → サインイン中で、識別子の変化なし・サインインなし・読み直しなしになることを確認します。
    func testSigningInKeepsPreviousIdentifier() {
        var relay = AdapterLinkSupervisionAuthenticationRelay()
        _ = relay.apply(phase: .signedIn, userIdentifier: "u1")
        XCTAssertEqual(relay.apply(phase: .signingIn, userIdentifier: nil), instruction(signedIn: false))
        XCTAssertEqual(relay.lastAccountIdentifier, "u1")
    }

    /// サインイン済みのまま識別子が変わったら、識別子だけを伝えます。
    ///
    /// 責務: 段階は同じで識別子が変わった時、サインイン有無を伝えないことを確認します。
    func testIdentifierChangeWithinSignedIn() {
        var relay = AdapterLinkSupervisionAuthenticationRelay()
        _ = relay.apply(phase: .signedIn, userIdentifier: "u1")
        XCTAssertEqual(relay.apply(phase: .signedIn, userIdentifier: "u2"), instruction(account: Change(accountIdentifier: "u2")))
    }

    /// 再確認の成功(サインアウト → サインイン済み)では、識別子とサインイン済みを伝えます。
    ///
    /// 責務: 確認できなかったサインアウトの後の再確認の成功で、監視がサインイン済みになる指示が出ることを確認します(受け入れ条件 15)。
    func testRecheckSuccessReportsSignedIn() {
        var relay = AdapterLinkSupervisionAuthenticationRelay()
        _ = relay.apply(phase: .checkingSession, userIdentifier: nil)
        _ = relay.apply(phase: .signedOut, userIdentifier: nil)
        XCTAssertEqual(relay.apply(phase: .signedIn, userIdentifier: "u1"), instruction(account: Change(accountIdentifier: "u1"), signedIn: true))
        XCTAssertEqual(relay.lastPhase, .signedIn)
    }

    /// アカウント削除中は、サインイン中でも識別子を nil にし、サインインなしを伝えます。
    ///
    /// 責務: サインイン済み → 削除中で、識別子が外れ、サインインなしになり、保持する識別子も nil になることを確認します。
    func testDeletingAccountClearsIdentifierAndReportsNotSignedIn() {
        var relay = AdapterLinkSupervisionAuthenticationRelay()
        _ = relay.apply(phase: .signedIn, userIdentifier: "u1")

        let result = relay.apply(phase: .deletingAccount, userIdentifier: "u1")

        XCTAssertEqual(result.accountIdentifierChange, Change(accountIdentifier: nil))
        XCTAssertEqual(result.isSignedIn, false)
        XCTAssertNil(relay.lastAccountIdentifier)
        XCTAssertEqual(relay.lastPhase, .deletingAccount)
    }

    /// 削除に失敗してサインイン済みへ戻ると、識別子とサインイン済みを再び伝えます。
    ///
    /// 責務: 削除中 → サインイン済みで、再試行に備えて監視が復帰する指示が出ることを確認します。
    func testReturningToSignedInAfterFailedDeletionReportsIdentifierAgain() {
        var relay = AdapterLinkSupervisionAuthenticationRelay()
        _ = relay.apply(phase: .signedIn, userIdentifier: "u1")
        _ = relay.apply(phase: .deletingAccount, userIdentifier: "u1")

        XCTAssertEqual(
            relay.apply(phase: .signedIn, userIdentifier: "u1"),
            instruction(account: Change(accountIdentifier: "u1"), signedIn: true)
        )
    }
}

import Foundation
import XCTest
@testable import ProjectZD8

/// `AuthenticationSessionModel` が、起動時のサインイン確認が照会の失敗だった時に、前面復帰と時間経過で上限つきに再確認することを検証します。
///
/// 仕様: U5 受け入れ条件 14〜18(B4)。待機は手動で進める Fake、照会の失敗は Fake のエラーで表し、待ちはすべて上限付きです。
@MainActor
final class AuthenticationSessionModelRecheckTests: XCTestCase {
    /// 保存済みのユーザー識別子です。
    private static let storedUser = "stored-user"

    /// 待機の Fake です。
    private var sleeper: AuthenticationRecheckSleepFake!
    /// 依存の組です。
    private var dependencies: AuthenticationModelDependencies!

    /// 責務: 照会が失敗する保存済みセッションの組を作ります。
    override func setUp() async throws {
        try await super.setUp()
        sleeper = AuthenticationRecheckSleepFake()
        dependencies = makeDependencies()
        dependencies.store.identifier = Self.storedUser
        dependencies.authorization.credentialState = .authorized
        dependencies.authorization.credentialStateError = URLError(.notConnectedToInternet)
    }

    /// 責務: 保留中の照会と待機を終わらせます。
    override func tearDown() async throws {
        dependencies?.authorization.releaseAllHeldCredentialChecks()
        sleeper?.drain()
        dependencies = nil
        sleeper = nil
        try await super.tearDown()
    }

    /// 待機の Fake を注入した認証モデルと Fake の組を作ります。
    ///
    /// 責務: 既存の認証モデルテストと同じ Fake 構成に、再確認の待機だけを差し替えます。
    /// - Returns: 依存の組。
    private func makeDependencies() -> AuthenticationModelDependencies {
        let authorization = AuthenticationModelAuthorizationPortFake()
        let store = AuthenticationModelSessionStorePortFake()
        let dataEraser = AuthenticationModelAccountDataEraserFake()
        let transfers = AuthenticationModelTransferRepositoryFake()
        let revocation = AuthenticationModelSessionRevocationPortFake()
        let model = AuthenticationSessionModel(
            state: AuthenticationState(),
            restoreSession: RestoreAuthenticationSessionUseCase(authorizationPort: authorization, sessionStore: store),
            signInWithApple: SignInWithAppleUseCase(authorizationPort: authorization, sessionStore: store),
            deleteAccount: DeleteAccountUseCase(
                sessionRevocation: revocation,
                sessionTransfers: transfers,
                vehicleDataEraser: AuthenticationModelVehicleDataEraserFake(),
                dataEraser: dataEraser,
                sessionStore: store
            ),
            remoteAccountLogout: RemoteAccountLogoutUseCase(dataEraser: dataEraser, sessionStore: store),
            sessionRevocation: revocation,
            recheckPolicy: .standard,
            recheckSleep: sleeper.sleep
        )
        return AuthenticationModelDependencies(
            model: model, authorization: authorization, store: store, dataEraser: dataEraser, transfers: transfers, revocation: revocation
        )
    }

    /// 起動時の確認を行い、照会の失敗で最初の再確認の待ち(5秒)が始まるまで進めます。
    ///
    /// 責務: `.appeared` を送り、`.sessionCheckFailed` と待機1件を上限付きで待ちます。
    private func launchWithFailedCheck(file: StaticString = #filePath, line: UInt = #line) async throws {
        dependencies.model.send(.appeared)
        try await BLEBoundedWaiter.waitUntil("確認の失敗と最初の待ち", file: file, line: line) {
            dependencies.model.state.failure == .sessionCheckFailed && sleeper.requestedDurations.count == 1
        }
        XCTAssertEqual(sleeper.requestedDurations, [.seconds(5)], file: file, line: line)
    }

    /// 照会の回数が指定に達するまで上限付きで待ちます。
    ///
    /// 責務: 資格状態の照会回数の到達を待ち、上限内に届かなければ失敗させて throw し、以降の手順(繰り返しを含む)を打ち切ります。
    /// - Parameter count: 待つ照会回数。
    /// - Throws: 上限内に届かなかった場合は `AdapterLinkBoundedAwaitTimeout`。
    private func waitForChecks(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async throws {
        guard try await BLEBoundedWaiter.waitUntil("照会 \(count) 回", file: file, line: line, condition: {
            dependencies.authorization.credentialStateRequestCount >= count
        }) else { throw AdapterLinkBoundedAwaitTimeout(description: "照会 \(count) 回") }
    }

    /// 確認できないままの状態(ログイン画面・エラー表示・セッションなし)であることを確かめます。
    ///
    /// 責務: 暫定的に保存済み識別子を信用していないことを確認します(受け入れ条件 16)。
    private func assertUnconfirmed(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(dependencies.model.state.phase, .signedOut, message, file: file, line: line)
        XCTAssertEqual(dependencies.model.state.failure, .sessionCheckFailed, message, file: file, line: line)
        XCTAssertNil(dependencies.model.state.session, message, file: file, line: line)
        XCTAssertNil(dependencies.revocation.observedIdentifier, message, file: file, line: line)
    }

    /// 確認の失敗の後、前面復帰で再確認し、成功すればサインイン済みになって失敗表示が消え、再確認の待ちも止まります。
    ///
    /// 責務: `.foregroundEntered` で照会が2回目になり、`.signedIn`・失敗なし・保存済み識別子のセッション・失効の監視・待機の取り消しを確認します
    /// (受け入れ条件 15 (a)・18)。
    func testForegroundRecheckSuccessSignsIn() async throws {
        try await launchWithFailedCheck()
        assertUnconfirmed()
        dependencies.authorization.credentialStateError = nil

        dependencies.model.send(.foregroundEntered)

        try await BLEBoundedWaiter.waitUntil("サインイン済み") { dependencies.model.state.phase == .signedIn }
        XCTAssertEqual(dependencies.authorization.credentialStateRequestCount, 2)
        XCTAssertNil(dependencies.model.state.failure)
        XCTAssertEqual(dependencies.model.state.session?.userIdentifier, Self.storedUser)
        XCTAssertEqual(dependencies.revocation.observedIdentifier, Self.storedUser)
        try await BLEBoundedWaiter.waitUntil("待ちの取り消し") { sleeper.pendingCount == 0 }
        XCTAssertEqual(sleeper.requestedDurations, [.seconds(5)], "解決の後は待たない")
    }

    /// 前面復帰の再確認の結果が本当に未サインイン(失効)なら、エラーなしのサインアウトになり、以後再確認しません。
    ///
    /// 責務: `revoked` で `.signedOut`・失敗なし・セッションなし・待機なし、次の前面復帰でも照会しないことを確認します(受け入れ条件 14・15)。
    func testForegroundRecheckRevokedSignsOutWithoutFailure() async throws {
        try await launchWithFailedCheck()
        dependencies.authorization.credentialStateError = nil
        dependencies.authorization.credentialState = .revoked

        dependencies.model.send(.foregroundEntered)

        try await BLEBoundedWaiter.waitUntil("失敗表示の解除") { dependencies.model.state.failure == nil }
        XCTAssertEqual(dependencies.model.state.phase, .signedOut)
        XCTAssertNil(dependencies.model.state.session)
        try await BLEBoundedWaiter.waitUntil("待ちの取り消し") { sleeper.pendingCount == 0 }
        dependencies.model.send(.foregroundEntered)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(dependencies.authorization.credentialStateRequestCount, 2, "本当に未サインインなら再確認しない")
    }

    /// 前面復帰の再確認でもまだ確認できなければ、確認できないままで、待ちを5秒から取り直します。
    ///
    /// 責務: 照会2回目の失敗の後もログイン画面・エラー表示・セッションなしで、新しい待機が5秒であることを確認します(受け入れ条件 15・16)。
    func testForegroundRecheckStillFailingRestartsSeries() async throws {
        try await launchWithFailedCheck()

        dependencies.model.send(.foregroundEntered)

        try await waitForChecks(2)
        try await BLEBoundedWaiter.waitUntil("新しい待ち") { sleeper.requestedDurations.count == 2 }
        XCTAssertEqual(sleeper.requestedDurations, [.seconds(5), .seconds(5)])
        XCTAssertTrue(sleeper.cancelledIndices.contains(0), "前の列の待ちは取り消す")
        assertUnconfirmed()
    }

    /// 時間経過では待ちごとに再確認し、合計10回で止まり、次の前面復帰で回数を取り直して再開します。
    ///
    /// 責務: 起動時1回+時間経過10回の照会・待ちの列・上限後に待たないこと、前面復帰で即時の照会と5秒の待ちが始まることを確認します
    /// (受け入れ条件 15 (b))。
    func testTimedRechecksStopAtLimitAndForegroundRestarts() async throws {
        try await launchWithFailedCheck()
        for attempt in 1...10 {
            guard try await BLEBoundedWaiter.waitUntil("\(attempt)件目の待ち", condition: { sleeper.pendingCount == 1 }) else { return }
            guard sleeper.finishOldest() else { return XCTFail("\(attempt)件目: 保留中の待機が無いため打ち切り") }
            try await waitForChecks(1 + attempt)
        }
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(dependencies.authorization.credentialStateRequestCount, 11)
        XCTAssertEqual(sleeper.requestedDurations, [.seconds(5), .seconds(15)] + Array(repeating: .seconds(60), count: 8))
        XCTAssertEqual(sleeper.pendingCount, 0, "上限の後は待たない")
        assertUnconfirmed("上限の後も確認できないまま")

        dependencies.model.send(.foregroundEntered)

        try await waitForChecks(12)
        try await BLEBoundedWaiter.waitUntil("取り直した待ち") { sleeper.requestedDurations.count == 11 }
        XCTAssertEqual(sleeper.requestedDurations.last, .seconds(5))
    }

    /// 時間経過の再確認が成功すれば、前面復帰を待たずにサインイン済みになります。
    ///
    /// 責務: 2回目の待ちの後の照会が成功すると `.signedIn` になり、以後待たないことを確認します(受け入れ条件 15 (b))。
    func testTimedRecheckSuccessSignsIn() async throws {
        try await launchWithFailedCheck()
        sleeper.finishOldest()
        try await waitForChecks(2)
        try await BLEBoundedWaiter.waitUntil("2件目の待ち") { sleeper.pendingCount == 1 }
        dependencies.authorization.credentialStateError = nil

        sleeper.finishOldest()

        try await BLEBoundedWaiter.waitUntil("サインイン済み") { dependencies.model.state.phase == .signedIn }
        XCTAssertNil(dependencies.model.state.failure)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(sleeper.requestedDurations, [.seconds(5), .seconds(15)])
    }

    /// 手動でサインインを始めたら再確認を止め、遅れて戻った再確認の結果は捨てます。
    ///
    /// 責務: 照会を保留した再確認の最中に手動サインインし、保留を解いた後もセッションが手動サインインのもので、待ちが増えないことを確認します
    /// (受け入れ条件 16)。
    func testManualSignInStopsRecheckAndDiscardsLateResult() async throws {
        try await launchWithFailedCheck()
        dependencies.authorization.holdsCredentialCheck = true
        dependencies.authorization.credentialStateError = nil
        dependencies.model.send(.foregroundEntered)
        try await BLEBoundedWaiter.waitUntil("照会の保留") { dependencies.authorization.heldCredentialCheckCount == 1 }
        dependencies.authorization.authorizationResult = .success(AppleAccountSession(userIdentifier: "manual-user"))

        dependencies.model.send(.loginTapped)
        dependencies.model.send(.disclaimerAccepted)
        try await BLEBoundedWaiter.waitUntil("手動サインイン") { dependencies.model.state.phase == .signedIn }
        dependencies.authorization.releaseAllHeldCredentialChecks()
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(dependencies.model.state.session?.userIdentifier, "manual-user", "遅れた再確認の結果で上書きしない")
        XCTAssertEqual(dependencies.model.state.phase, .signedIn)
        XCTAssertEqual(sleeper.pendingCount, 0, "手動サインインの後は再確認の待ちを残さない")
        XCTAssertEqual(sleeper.requestedDurations, [.seconds(5)])
    }

    /// 本当に未サインイン(保存なし)で起動した時は、時間経過でも前面復帰でも再確認しません。
    ///
    /// 責務: 待機0件、前面復帰の後も照会0回であることを確認します(受け入れ条件 14)。
    func testGenuinelySignedOutNeverRechecks() async throws {
        dependencies.store.identifier = nil
        dependencies.model.send(.appeared)
        try await BLEBoundedWaiter.waitUntil("サインアウト") { dependencies.model.state.phase == .signedOut }

        dependencies.model.send(.foregroundEntered)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(sleeper.requestedDurations, [])
        XCTAssertEqual(dependencies.authorization.credentialStateRequestCount, 0)
        XCTAssertNil(dependencies.model.state.failure)
    }

    /// サインイン済みと確認中の前面復帰では、再確認しません。
    ///
    /// 責務: 起動前(確認中)と、照会成功でサインイン済みになった後の前面復帰で、照会回数が増えないことを確認します。
    func testForegroundWhileCheckingOrSignedInDoesNotRecheck() async throws {
        dependencies.model.send(.foregroundEntered)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(dependencies.authorization.credentialStateRequestCount, 0, "確認中")

        dependencies.authorization.credentialStateError = nil
        dependencies.model.send(.appeared)
        try await BLEBoundedWaiter.waitUntil("サインイン済み") { dependencies.model.state.phase == .signedIn }
        dependencies.model.send(.foregroundEntered)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(dependencies.authorization.credentialStateRequestCount, 1, "サインイン済み")
        XCTAssertEqual(sleeper.requestedDurations, [])
    }
}

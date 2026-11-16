import XCTest
@testable import ProjectZD8

/// アカウント削除の開始から終了までの認証段階と、記録の終了待ち・失敗の分類を仕様から検証します。
///
/// 仕様: 削除開始で `.deletingAccount`。成功で `.signedOut`、失敗で `.signedIn` と `accountDeletionPhase == .failed` に戻し再試行できる。
/// 記録の終了待ちが失敗したらクラウド削除へ進まない。
@MainActor
final class AuthenticationSessionModelAccountDeletionTests: XCTestCase {
    /// 待機の上限回数です。実時間は待たず `Task.yield()` だけを繰り返します。
    private static let maximumYields = 5_000

    /// 削除開始で `.deletingAccount` になり、記録の終了待ちが済むまでクラウド削除へ進まないことを検証します。
    ///
    /// 責務: 終了待ちの保留中に、認証段階・削除段階・クラウド削除の未実行を確認します。
    func testDeletionEntersDeletingAccountAndWaitsForDrainBeforeCloudDeletion() async {
        let fixture = makeFixture()
        fixture.drain.holds = true
        defer { fixture.drain.release() }

        confirmDeletion(fixture)
        let reached = await waitUntil { fixture.drain.isWaiting }

        XCTAssertTrue(reached, "記録の終了待ちに到達しませんでした(タイムアウト)。")
        XCTAssertEqual(fixture.model.state.phase, .deletingAccount)
        XCTAssertEqual(fixture.model.state.accountDeletionPhase, .deleting)
        XCTAssertTrue(fixture.transfers.deletedAccountIdentifiers.isEmpty)
    }

    /// 削除中の再確認とキャンセルは無視され、削除は1回だけ進むことを検証します。
    ///
    /// 責務: 削除中に `accountDeletionConfirmed` と `accountDeletionCancelled` を送っても状態が変わらず、終了待ちが1回だけであることを確認します。
    func testConfirmAndCancelAreIgnoredWhileDeleting() async {
        let fixture = makeFixture()
        fixture.drain.holds = true
        defer { fixture.drain.release() }
        confirmDeletion(fixture)
        _ = await waitUntil { fixture.drain.isWaiting }

        fixture.model.send(.accountDeletionConfirmed)
        fixture.model.send(.accountDeletionCancelled)

        XCTAssertEqual(fixture.model.state.phase, .deletingAccount)
        XCTAssertEqual(fixture.model.state.accountDeletionPhase, .deleting)
        XCTAssertEqual(fixture.drain.callCount, 1)
    }

    /// 削除が成功したらサインアウトになり、削除状態と失敗が空に戻ることを検証します。
    ///
    /// 責務: 成功後の認証段階・セッション・削除段階・失敗・失効監視の停止を確認します。
    func testSuccessSignsOutAndResetsDeletionState() async {
        let fixture = makeFixture()

        confirmDeletion(fixture)
        let finished = await waitUntil { fixture.model.state.phase == .signedOut }

        XCTAssertTrue(finished, "削除が完了しませんでした(タイムアウト)。")
        XCTAssertNil(fixture.model.state.session)
        XCTAssertEqual(fixture.model.state.accountDeletionPhase, .idle)
        XCTAssertNil(fixture.model.state.accountDeletionFailure)
        XCTAssertEqual(fixture.transfers.deletedAccountIdentifiers, ["delete-user"])
        XCTAssertEqual(fixture.revocation.stopCount, 1)
    }

    /// 記録の終了待ちがタイムアウトしたら、クラウド削除へ進まず、サインイン済みへ戻って `.acquisitionTimedOut` になることを検証します。
    ///
    /// 責務: 終了待ちの失敗で、削除が1件も実行されず、再試行できる状態に戻ることを確認します。
    func testDrainTimeoutReturnsToSignedInWithoutDeleting() async {
        let fixture = makeFixture()
        fixture.drain.error = AccountDeletionAcquisitionDrainError.timedOut

        confirmDeletion(fixture)
        let finished = await waitUntil { fixture.model.state.accountDeletionPhase == .failed }

        XCTAssertTrue(finished, "失敗状態になりませんでした(タイムアウト)。")
        XCTAssertEqual(fixture.model.state.phase, .signedIn)
        XCTAssertEqual(fixture.model.state.accountDeletionFailure, .acquisitionTimedOut)
        XCTAssertNotNil(fixture.model.state.session)
        XCTAssertTrue(fixture.transfers.deletedAccountIdentifiers.isEmpty)
        XCTAssertTrue(fixture.dataEraser.erasedIdentifiers.isEmpty)
    }

    /// 削除の失敗は分類境界の結果で表示し、サインイン済みへ戻して再試行で成功できることを検証します。
    ///
    /// 責務: 失敗時の段階・原因を確認し、原因を取り除いた再試行が成功してサインアウトになることを確認します。
    func testFailureIsClassifiedAndRetryCanSucceed() async {
        let fixture = makeFixture(classifier: FixedClassifier(result: .serviceBusy))
        fixture.store.removeError = AuthenticationSessionStoreError.unavailable

        confirmDeletion(fixture)
        let failed = await waitUntil { fixture.model.state.accountDeletionPhase == .failed }

        XCTAssertTrue(failed, "失敗状態になりませんでした(タイムアウト)。")
        XCTAssertEqual(fixture.model.state.phase, .signedIn)
        XCTAssertEqual(fixture.model.state.accountDeletionFailure, .serviceBusy)

        fixture.store.removeError = nil
        fixture.model.send(.accountDeletionConfirmed)
        let finished = await waitUntil { fixture.model.state.phase == .signedOut }

        XCTAssertTrue(finished, "再試行が完了しませんでした(タイムアウト)。")
        XCTAssertEqual(fixture.model.state.accountDeletionPhase, .idle)
        XCTAssertNil(fixture.model.state.accountDeletionFailure)
        XCTAssertEqual(fixture.drain.callCount, 2)
    }

    /// 分類境界が無い場合、削除の失敗は `.deletionFailed` になることを検証します。
    ///
    /// 責務: 分類境界なしの既定の原因を確認します。
    func testFailureWithoutClassifierIsDeletionFailed() async {
        let fixture = makeFixture()
        fixture.store.removeError = AuthenticationSessionStoreError.unavailable

        confirmDeletion(fixture)
        let failed = await waitUntil { fixture.model.state.accountDeletionPhase == .failed }

        XCTAssertTrue(failed, "失敗状態になりませんでした(タイムアウト)。")
        XCTAssertEqual(fixture.model.state.accountDeletionFailure, .deletionFailed)
    }

    /// 削除の再試行を始めると、前回の失敗表示が消えることを検証します。
    ///
    /// 責務: 失敗後の再確定で、削除中に失敗の原因が残らないことを確認します。
    func testRetryClearsPreviousFailureWhileDeleting() async {
        let fixture = makeFixture()
        fixture.drain.error = AccountDeletionAcquisitionDrainError.timedOut
        confirmDeletion(fixture)
        _ = await waitUntil { fixture.model.state.accountDeletionPhase == .failed }
        fixture.drain.error = nil
        fixture.drain.holds = true
        defer { fixture.drain.release() }

        fixture.model.send(.accountDeletionConfirmed)
        _ = await waitUntil { fixture.drain.isWaiting }

        XCTAssertEqual(fixture.model.state.phase, .deletingAccount)
        XCTAssertNil(fixture.model.state.accountDeletionFailure)
    }

    /// 検証対象と各Fakeの組です。
    private struct Fixture {
        /// 検証対象のモデルです。
        let model: AuthenticationSessionModel
        /// 記録の終了待ちのFakeです。
        let drain: AccountDeletionAcquisitionDrainFake
        /// セッション保存のFakeです。
        let store: AuthenticationModelSessionStorePortFake
        /// クラウド運転データ削除のFakeです。
        let transfers: ConnectionSessionTransferRepositoryFake
        /// ローカルデータ消去のFakeです。
        let dataEraser: AuthenticationModelAccountDataEraserFake
        /// 失効のFakeです。
        let revocation: AuthenticationModelSessionRevocationPortFake
    }

    /// 失敗の原因を固定で返す分類境界です。
    private struct FixedClassifier: AccountDeletionFailureClassifying {
        /// 返す原因です。
        let result: AccountDeletionFailure

        /// 固定の原因を返します。
        ///
        /// 責務: 分類の結果を固定します。
        /// - Parameter _: 使用しないエラー。
        /// - Returns: 固定の原因。
        func failure(for _: Error) -> AccountDeletionFailure { result }
    }

    /// サインイン済みで、終了待ちのFakeを結び付けたモデルを組み立てます。
    ///
    /// 責務: 共有Fakeから認証モデルを生成し、終了待ちの境界を差し込みます。
    /// - Parameter classifier: 失敗の分類境界。省略時は分類しません。
    /// - Returns: モデルとFakeの組。
    private func makeFixture(classifier: (any AccountDeletionFailureClassifying)? = nil) -> Fixture {
        let session = AppleAccountSession(userIdentifier: "delete-user")
        let authorization = AuthenticationModelAuthorizationPortFake()
        let store = AuthenticationModelSessionStorePortFake()
        store.identifier = session.userIdentifier
        let dataEraser = AuthenticationModelAccountDataEraserFake()
        let transfers = ConnectionSessionTransferRepositoryFake()
        let revocation = AuthenticationModelSessionRevocationPortFake()
        let model = AuthenticationSessionModel(
            state: AuthenticationState(phase: .signedIn, session: session),
            restoreSession: RestoreAuthenticationSessionUseCase(authorizationPort: authorization, sessionStore: store),
            signInWithApple: SignInWithAppleUseCase(authorizationPort: authorization, sessionStore: store),
            deleteAccount: DeleteAccountUseCase(
                sessionRevocation: revocation,
                cloudErasers: AccountCloudDataErasers(
                    sessionTransfers: transfers,
                    vehicleDataEraser: AuthenticationModelVehicleDataEraserFake(),
                    maintenanceDataEraser: AuthenticationModelMaintenanceDataEraserFake()
                ),
                dataEraser: dataEraser,
                sessionStore: store
            ),
            remoteAccountLogout: RemoteAccountLogoutUseCase(dataEraser: dataEraser, sessionStore: store),
            sessionRevocation: revocation,
            deletionFailureClassifier: classifier
        )
        let drain = AccountDeletionAcquisitionDrainFake()
        model.acquisitionDrain = drain
        return Fixture(model: model, drain: drain, store: store, transfers: transfers, dataEraser: dataEraser, revocation: revocation)
    }

    /// 警告・確認を経て削除を確定します。
    ///
    /// 責務: 削除の確定までの操作列を共通化します。
    /// - Parameter fixture: 検証対象の組。
    private func confirmDeletion(_ fixture: Fixture) {
        fixture.model.send(.accountDeletionRequested)
        fixture.model.send(.accountDeletionWarningConfirmed)
        fixture.model.send(.accountDeletionConfirmed)
    }

    /// 上限付きで条件が成立するまで実行機会を譲ります。
    ///
    /// 責務: 実時間を待たず、上限回数内に条件が成立するかを返します。
    /// - Parameter condition: 成立を判定する処理。
    /// - Returns: 上限内に成立したか。
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<Self.maximumYields {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }
}

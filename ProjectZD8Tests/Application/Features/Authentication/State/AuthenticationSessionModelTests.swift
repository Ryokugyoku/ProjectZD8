import XCTest
@testable import ProjectZD8

/// 認証入口モデルの明示同意と非同期状態遷移を検証します。
@MainActor
final class AuthenticationSessionModelTests: XCTestCase {
    /// 初期表示が保存済みセッションを確認してログアウト状態へ遷移することを検証します。
    ///
    /// 責務: appeared操作がセッション復元ユースケースを一度だけ実行することを確認します。
    func testAppearedRestoresMissingSessionAsSignedOut() async {
        let dependencies = makeDependencies()
        let model = dependencies.model

        model.send(.appeared)
        await waitForTasks()

        XCTAssertEqual(model.state.phase, .signedOut)
        XCTAssertNil(model.state.session)
        XCTAssertEqual(dependencies.authorization.credentialStateRequestCount, 0)
    }

    /// ログイン操作だけではApple認証を開始せず免責事項を提示することを検証します。
    ///
    /// 責務: loginTapped操作がApple認証前の明示同意状態だけを開くことを確認します。
    func testLoginTapPresentsDisclaimerBeforeAuthorization() {
        let dependencies = makeDependencies(state: AuthenticationState(phase: .signedOut))

        dependencies.model.send(.loginTapped)

        XCTAssertTrue(dependencies.model.state.isDisclaimerPresented)
        XCTAssertEqual(dependencies.authorization.authorizationRequestCount, 0)
    }

    /// 免責事項が未表示の同意操作でApple認証を開始しないことを検証します。
    ///
    /// 責務: 明示同意画面を経ていない認証要求がApplication状態で拒否されることを確認します。
    func testAcceptanceWithoutPresentedDisclaimerDoesNotAuthorize() async {
        let dependencies = makeDependencies(state: AuthenticationState(phase: .signedOut))

        dependencies.model.send(.disclaimerAccepted)
        await waitForTasks()

        XCTAssertEqual(dependencies.authorization.authorizationRequestCount, 0)
        XCTAssertEqual(dependencies.model.state.phase, .signedOut)
    }

    /// 免責同意後のApple認証成功が認証済み状態になることを検証します。
    ///
    /// 責務: 明示同意済みApple認証結果がルートアクセス許可へ遷移することを確認します。
    func testAcceptedDisclaimerCompletesAppleSignIn() async {
        let dependencies = makeDependencies(state: AuthenticationState(phase: .signedOut))
        dependencies.authorization.authorizationResult = .success(
            AppleAccountSession(userIdentifier: "accepted-user")
        )

        dependencies.model.send(.loginTapped)
        dependencies.model.send(.disclaimerAccepted)
        await waitForTasks()

        XCTAssertEqual(dependencies.model.state.phase, .signedIn)
        XCTAssertEqual(dependencies.model.state.session?.userIdentifier, "accepted-user")
        XCTAssertEqual(dependencies.store.identifier, "accepted-user")
        XCTAssertEqual(dependencies.revocation.registeredIdentifiers, ["accepted-user"])
        XCTAssertEqual(dependencies.revocation.observedIdentifier, "accepted-user")
    }

    /// Apple認証キャンセルが失敗表示なしでログイン待機へ戻ることを検証します。
    ///
    /// 責務: ユーザーキャンセルを再試行可能な通常のログアウト状態へ変換します。
    func testCancelledAppleSignInReturnsToSignedOutWithoutFailure() async {
        let dependencies = makeDependencies(state: AuthenticationState(phase: .signedOut))
        dependencies.authorization.authorizationResult = .failure(
            AppleAccountAuthorizationError.cancelled
        )

        dependencies.model.send(.loginTapped)
        dependencies.model.send(.disclaimerAccepted)
        await waitForTasks()

        XCTAssertEqual(dependencies.model.state.phase, .signedOut)
        XCTAssertNil(dependencies.model.state.failure)
    }

    /// アカウント削除が警告と削除事項の確認を経るまで実行されないことを検証します。
    ///
    /// 責務: 2段階確認より前の操作が保存データ消去を開始しないことを確認します。
    func testAccountDeletionRequiresWarningAndReviewBeforeErasure() {
        let session = AppleAccountSession(userIdentifier: "delete-user")
        let dependencies = makeDependencies(
            state: AuthenticationState(phase: .signedIn, session: session)
        )

        dependencies.model.send(.accountDeletionRequested)
        XCTAssertEqual(dependencies.model.state.accountDeletionPhase, .warning)
        XCTAssertEqual(dependencies.dataEraser.erasedIdentifiers, [])

        dependencies.model.send(.accountDeletionWarningConfirmed)
        XCTAssertEqual(dependencies.model.state.accountDeletionPhase, .reviewing)
        XCTAssertEqual(dependencies.dataEraser.erasedIdentifiers, [])
    }

    /// 最終確認後に全データとログイン識別子を削除してログアウトすることを検証します。
    ///
    /// 責務: 最終削除操作がデータ消去とログイン画面への状態遷移を完了することを確認します。
    func testConfirmedAccountDeletionErasesDataAndSignsOut() async {
        let session = AppleAccountSession(userIdentifier: "delete-user")
        let dependencies = makeDependencies(
            state: AuthenticationState(phase: .signedIn, session: session)
        )
        dependencies.store.identifier = session.userIdentifier

        dependencies.model.send(.accountDeletionRequested)
        dependencies.model.send(.accountDeletionWarningConfirmed)
        dependencies.model.send(.accountDeletionConfirmed)
        await waitForTasks()

        XCTAssertEqual(dependencies.dataEraser.erasedIdentifiers, ["delete-user"])
        XCTAssertEqual(dependencies.transfers.deletedAccountIdentifiers, ["delete-user"])
        XCTAssertEqual(dependencies.revocation.publishedIdentifiers, ["delete-user"])
        XCTAssertNil(dependencies.store.identifier)
        XCTAssertNil(dependencies.model.state.session)
        XCTAssertEqual(dependencies.model.state.phase, .signedOut)
        XCTAssertEqual(dependencies.model.state.accountDeletionPhase, .idle)
    }

    /// ログイン識別子の削除失敗時に認証状態を保持して再試行可能にすることを検証します。
    ///
    /// 責務: 部分失敗をログアウト成功へ変換せず削除確認画面へ保持することを確認します。
    func testCredentialRemovalFailureKeepsSignedInRetryState() async {
        let session = AppleAccountSession(userIdentifier: "retry-user")
        let dependencies = makeDependencies(
            state: AuthenticationState(phase: .signedIn, session: session)
        )
        dependencies.store.identifier = session.userIdentifier
        dependencies.store.removeError = AuthenticationSessionStoreError.unavailable

        dependencies.model.send(.accountDeletionRequested)
        dependencies.model.send(.accountDeletionWarningConfirmed)
        dependencies.model.send(.accountDeletionConfirmed)
        await waitForTasks()

        XCTAssertEqual(dependencies.dataEraser.erasedIdentifiers, ["retry-user"])
        XCTAssertEqual(dependencies.model.state.phase, .signedIn)
        XCTAssertEqual(dependencies.model.state.session, session)
        XCTAssertEqual(dependencies.model.state.accountDeletionPhase, .failed)
        XCTAssertEqual(dependencies.model.state.accountDeletionFailure, .deletionFailed)
    }

    /// 復元した認証セッションが新しい失効世代を受理せず監視を開始することを検証します。
    ///
    /// 責務: 保存済みセッション復元を他端末失効の継続監視へ接続することを確認します。
    func testRestoredSessionStartsRevocationObservationWithoutRegisteringCurrentMarker() async {
        let dependencies = makeDependencies()
        dependencies.store.identifier = "restored-user"
        dependencies.authorization.credentialState = .authorized

        dependencies.model.send(.appeared)
        await waitForTasks()

        XCTAssertEqual(dependencies.model.state.phase, .signedIn)
        XCTAssertEqual(dependencies.revocation.observedIdentifier, "restored-user")
        XCTAssertEqual(dependencies.revocation.registeredIdentifiers, [])
    }

    /// 他端末の失効通知が現在端末のデータとセッションを削除してログアウトすることを検証します。
    ///
    /// 責務: 遠隔失効コールバックをローカル消去とログイン画面状態へ変換することを確認します。
    func testRemoteRevocationErasesLocalDataAndSignsOut() {
        let session = AppleAccountSession(userIdentifier: "remote-user")
        let dependencies = makeDependencies(
            state: AuthenticationState(phase: .signedIn, session: session)
        )
        dependencies.store.identifier = session.userIdentifier

        dependencies.revocation.deliverRevocation()

        XCTAssertEqual(dependencies.dataEraser.erasedIdentifiers, ["remote-user"])
        XCTAssertEqual(dependencies.revocation.publishedIdentifiers, [])
        XCTAssertNil(dependencies.store.identifier)
        XCTAssertNil(dependencies.model.state.session)
        XCTAssertEqual(dependencies.model.state.phase, .signedOut)
        XCTAssertEqual(dependencies.revocation.stopCount, 1)
    }

    /// 他端末ログアウトのKeychain削除失敗を案内しつつ現在表示をログイン画面へ戻すことを検証します。
    ///
    /// 責務: 遠隔失効の端末内永続化失敗を成功扱いせず区別可能なログイン画面状態へ保持します。
    func testRemoteRevocationPersistenceFailureSignsOutWithFailureNotice() {
        let session = AppleAccountSession(userIdentifier: "remote-retry-user")
        let dependencies = makeDependencies(
            state: AuthenticationState(phase: .signedIn, session: session)
        )
        dependencies.store.identifier = session.userIdentifier
        dependencies.store.removeError = AuthenticationSessionStoreError.unavailable

        dependencies.revocation.deliverRevocation()

        XCTAssertEqual(dependencies.dataEraser.erasedIdentifiers, ["remote-retry-user"])
        XCTAssertEqual(dependencies.store.identifier, "remote-retry-user")
        XCTAssertEqual(dependencies.model.state.phase, .signedOut)
        XCTAssertEqual(dependencies.model.state.failure, .remoteLogoutPersistenceFailed)
    }

    /// テスト用依存関係と認証モデルをまとめて生成します。
    ///
    /// 責務: 1件の認証モデルテストへ共有Fakeを同一構成で注入します。
    /// - Parameter state: モデルへ与える初期認証状態。未指定時はセッション確認中の状態を生成します。
    /// - Returns: 認証モデル、Apple認証Fake、保存Fakeの組。
    private func makeDependencies(
        state: AuthenticationState? = nil
    ) -> AuthenticationModelDependencies {
        let authorization = AuthenticationModelAuthorizationPortFake()
        let store = AuthenticationModelSessionStorePortFake()
        let dataEraser = AuthenticationModelAccountDataEraserFake()
        let transfers = AuthenticationModelTransferRepositoryFake()
        let vehicleDataEraser = AuthenticationModelVehicleDataEraserFake()
        let revocation = AuthenticationModelSessionRevocationPortFake()
        let model = AuthenticationSessionModel(
            state: state ?? AuthenticationState(),
            restoreSession: RestoreAuthenticationSessionUseCase(
                authorizationPort: authorization,
                sessionStore: store
            ),
            signInWithApple: SignInWithAppleUseCase(
                authorizationPort: authorization,
                sessionStore: store
            ),
            deleteAccount: DeleteAccountUseCase(
                sessionRevocation: revocation,
                sessionTransfers: transfers,
                vehicleDataEraser: vehicleDataEraser,
                dataEraser: dataEraser,
                sessionStore: store
            ),
            remoteAccountLogout: RemoteAccountLogoutUseCase(
                dataEraser: dataEraser,
                sessionStore: store
            ),
            sessionRevocation: revocation
        )
        return AuthenticationModelDependencies(
            model: model,
            authorization: authorization,
            store: store,
            dataEraser: dataEraser,
            transfers: transfers,
            revocation: revocation
        )
    }

    /// モデルが開始したMainActorタスクへ実行機会を与えます。
    ///
    /// 責務: 即時Fakeを待機する認証モデルタスクをテスト検証前に完了させます。
    private func waitForTasks() async {
        for _ in 0..<8 {
            await Task.yield()
        }
    }
}

/// 認証モデルテストで共有するモデルとFakeの組です。
@MainActor
private struct AuthenticationModelDependencies {
    /// 検証対象の認証セッションモデルです。
    let model: AuthenticationSessionModel

    /// Apple認証要求を記録するFakeです。
    let authorization: AuthenticationModelAuthorizationPortFake

    /// セッション保存結果を記録するFakeです。
    let store: AuthenticationModelSessionStorePortFake

    /// 削除対象識別子を記録するアカウントデータ消去Fakeです。
    let dataEraser: AuthenticationModelAccountDataEraserFake

    /// CloudKit運転データ削除を記録するFakeです。
    let transfers: AuthenticationModelTransferRepositoryFake

    /// 失効登録、発行、監視を記録するFakeです。
    let revocation: AuthenticationModelSessionRevocationPortFake
}

/// 認証モデルテストでApple認証結果を制御します。
@MainActor
private final class AuthenticationModelAuthorizationPortFake: AppleAccountAuthorizationPort {
    /// Apple認証要求が返す結果です。
    var authorizationResult: Result<AppleAccountSession, Error> = .success(
        AppleAccountSession(userIdentifier: "model-user")
    )

    /// Apple資格状態照会が返す状態です。
    var credentialState: AppleAccountCredentialState = .notFound

    /// Apple認証要求の実行回数です。
    private(set) var authorizationRequestCount = 0

    /// Apple資格状態照会の実行回数です。
    private(set) var credentialStateRequestCount = 0

    /// 設定されたApple認証結果を返します。
    ///
    /// 責務: Apple認証要求を記録してテスト指定結果を返します。
    /// - Returns: テストが設定した認証セッション。
    /// - Throws: テストが設定した認証失敗。
    func authorize() async throws -> AppleAccountSession {
        authorizationRequestCount += 1
        return try authorizationResult.get()
    }

    /// 設定されたApple資格状態を返します。
    ///
    /// 責務: 資格状態照会を記録してテスト指定状態を返します。
    /// - Parameter userIdentifier: モデルが照会したAppleユーザー識別子。
    /// - Returns: テストが設定したApple資格状態。
    func credentialState(for userIdentifier: String) async throws -> AppleAccountCredentialState {
        credentialStateRequestCount += 1
        return credentialState
    }
}

/// 認証モデルテストでセッション保存結果を記録します。
private final class AuthenticationModelSessionStorePortFake: AuthenticationSessionStorePort {
    /// 現在保存されているテスト用Appleユーザー識別子です。
    var identifier: String?

    /// セッション削除時に送出するテスト指定エラーです。
    var removeError: Error?

    /// 現在のテスト用識別子を返します。
    ///
    /// 責務: モデルの復元ユースケースへ保存済み識別子を返します。
    /// - Returns: 現在保存されているテスト用識別子。
    func loadUserIdentifier() throws -> String? {
        identifier
    }

    /// テスト用識別子を置き換えます。
    ///
    /// 責務: モデルのログインユースケースが保存した識別子を記録します。
    /// - Parameter userIdentifier: 保存を要求されたAppleユーザー識別子。
    func saveUserIdentifier(_ userIdentifier: String) throws {
        identifier = userIdentifier
    }

    /// テスト用識別子を削除します。
    ///
    /// 責務: モデルの復元ユースケースが無効化した識別子を除去します。
    func removeUserIdentifier() throws {
        if let removeError {
            throw removeError
        }
        identifier = nil
    }
}

/// 認証モデルテストでアカウントデータ消去要求を記録します。
@MainActor
private final class AuthenticationModelAccountDataEraserFake: AccountDataErasurePort {
    /// 消去を要求されたAppleユーザー識別子です。
    private(set) var erasedIdentifiers: [String] = []

    /// 指定識別子を消去要求履歴へ追加します。
    ///
    /// 責務: 1件のデータ消去要求をテストから観測可能な履歴へ記録します。
    /// - Parameter userIdentifier: 消去を要求されたAppleユーザー識別子。
    func eraseAllData(for userIdentifier: String) throws {
        erasedIdentifiers.append(userIdentifier)
    }
}

/// 認証モデルテストでCloudKit運転データ操作を記録します。
@MainActor
private final class AuthenticationModelTransferRepositoryFake: ConnectionSessionTransferRepository {
    /// 全削除を要求されたアカウント識別子です。
    private(set) var deletedAccountIdentifiers: [String] = []

    /// このテストでは転送送信を使用しません。
    ///
    /// 責務: テスト対象外の送信要求を固定Digestで満たします。
    /// - Parameters:
    ///   - package: 使用しない転送Payload。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 固定Digest。
    func upload(_ package: ConnectionSessionTransferPackage, for accountIdentifier: String) async throws -> String { "digest" }

    /// このテストでは転送を返しません。
    ///
    /// 責務: テスト対象外の転送取得要求へ空配列を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func downloadTransfers(for accountIdentifier: String) async throws -> [VerifiedConnectionSessionTransfer] { [] }

    /// このテストでは受領証公開を使用しません。
    ///
    /// 責務: テスト対象外の受領証公開要求を副作用なしで満たします。
    /// - Parameters:
    ///   - receipt: 使用しないMac受領証。
    ///   - sessionID: 使用しないセッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func publishMacReceipt(
        _ receipt: ConnectionSessionMacImportReceipt,
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws {}

    /// このテストでは受領証を返しません。
    ///
    /// 責務: テスト対象外の受領証取得要求へ空配列を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func downloadMacReceipts(
        for accountIdentifier: String
    ) async throws -> [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] { [] }

    /// このテストでは削除マーカーを返しません。
    ///
    /// 責務: テスト対象外の削除マーカー取得へ空集合を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空集合。
    func deletedSessionIDs(for accountIdentifier: String) async throws -> Set<ConnectionSessionID> { [] }

    /// このテストではセッション単位削除を使用しません。
    ///
    /// 責務: テスト対象外のセッション削除要求を副作用なしで満たします。
    /// - Parameters:
    ///   - sessionID: 使用しないセッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func deleteSession(_ sessionID: ConnectionSessionID, for accountIdentifier: String) async throws {}

    /// CloudKit運転データ全削除を記録します。
    ///
    /// 責務: 1件のアカウント識別子を削除要求履歴へ追加します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func deleteAll(for accountIdentifier: String) async throws {
        deletedAccountIdentifiers.append(accountIdentifier)
    }
}

/// 認証モデルテストで車両データ削除境界を再現します。
@MainActor
private final class AuthenticationModelVehicleDataEraserFake: AccountVehicleDataErasurePort {
    /// 全削除されたアカウント識別子です。
    private(set) var deletedAccountIdentifiers: [String] = []

    /// 車両カタログ全削除を記録します。
    ///
    /// 責務: 1件のアカウント識別子を車両データ削除履歴へ追加します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func deleteAllVehicleData(for accountIdentifier: String) async throws {
        deletedAccountIdentifiers.append(accountIdentifier)
    }

    /// このテストでは端末キャッシュに車両を保持しません。
    ///
    /// 責務: テスト対象外のローカル車両ID照会へ空配列を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func localVehicleIDs(for accountIdentifier: String) -> [VehicleID] { [] }

    /// このテストでは端末キャッシュ単独削除を使用しません。
    ///
    /// 責務: テスト対象外の車両キャッシュ削除要求を副作用なしで満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    func removeLocalVehicleCache(for accountIdentifier: String) {}
}

/// 認証モデルテストで端末間セッション失効操作を記録します。
@MainActor
private final class AuthenticationModelSessionRevocationPortFake: AccountSessionRevocationPort {
    /// 現在世代の受理を要求されたユーザー識別子です。
    private(set) var registeredIdentifiers: [String] = []

    /// 失効発行を要求されたユーザー識別子です。
    private(set) var publishedIdentifiers: [String] = []

    /// 現在監視中のユーザー識別子です。
    private(set) var observedIdentifier: String?

    /// 監視終了を要求された回数です。
    private(set) var stopCount = 0

    /// テストから実行する現在の失効通知処理です。
    private var receiveRevocation: (() -> Void)?

    /// 現在世代の受理要求を記録します。
    ///
    /// 責務: 1件のセッション基準登録をテストから検証可能な履歴へ追加します。
    /// - Parameter userIdentifier: 登録を要求されたユーザー識別子。
    func registerCurrentSession(for userIdentifier: String) {
        registeredIdentifiers.append(userIdentifier)
    }

    /// 新しい失効世代の発行要求を記録します。
    ///
    /// 責務: 1件の失効発行をテストから検証可能な履歴へ追加します。
    /// - Parameter userIdentifier: 発行を要求されたユーザー識別子。
    func publishRevocation(for userIdentifier: String) {
        publishedIdentifiers.append(userIdentifier)
    }

    /// 失効監視対象とコールバックを保持します。
    ///
    /// 責務: 1件の失効監視要求をテストから起動可能なコールバックへ保存します。
    /// - Parameters:
    ///   - userIdentifier: 監視を要求されたユーザー識別子。
    ///   - receive: テストが失効を模擬するときに実行する処理。
    func startObserving(
        for userIdentifier: String,
        receive: @escaping () -> Void
    ) {
        observedIdentifier = userIdentifier
        receiveRevocation = receive
    }

    /// 失効監視の終了要求を記録します。
    ///
    /// 責務: 現在のFake監視状態を未購読へ戻して終了回数を加算します。
    func stopObserving() {
        stopCount += 1
        observedIdentifier = nil
        receiveRevocation = nil
    }

    /// 保存済み失効コールバックをテストから実行します。
    ///
    /// 責務: 他端末からの失効受信を1回のFakeコールバック実行として再現します。
    func deliverRevocation() {
        receiveRevocation?()
    }
}

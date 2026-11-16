import XCTest
@testable import ProjectZD8

/// Apple認証セッションの復元と保存ユースケースを検証します。
@MainActor
final class AuthenticationUseCaseTests: XCTestCase {
    /// 未保存の場合にApple資格照会を行わずログアウト状態になることを検証します。
    ///
    /// 責務: 空のセッション保存領域が未認証結果へ変換されることを確認します。
    func testRestoreWithoutStoredIdentifierReturnsSignedOut() async throws {
        let authorization = AuthenticationAuthorizationPortFake()
        let store = AuthenticationSessionStorePortFake()
        let useCase = RestoreAuthenticationSessionUseCase(
            authorizationPort: authorization,
            sessionStore: store
        )

        let session = try await useCase.execute()

        XCTAssertNil(session)
        XCTAssertEqual(authorization.credentialStateRequestCount, 0)
    }

    /// Appleが許可中と返した保存済みセッションを復元できることを検証します。
    ///
    /// 責務: 保存済み識別子のauthorized資格状態が認証済み結果になることを確認します。
    func testRestoreAuthorizedIdentifierReturnsSignedIn() async throws {
        let authorization = AuthenticationAuthorizationPortFake()
        authorization.credentialState = .authorized
        let store = AuthenticationSessionStorePortFake(identifier: "apple-user")
        let useCase = RestoreAuthenticationSessionUseCase(
            authorizationPort: authorization,
            sessionStore: store
        )

        let session = try await useCase.execute()

        XCTAssertEqual(session?.userIdentifier, "apple-user")
        XCTAssertEqual(authorization.requestedUserIdentifier, "apple-user")
        XCTAssertFalse(store.didRemoveIdentifier)
    }

    /// 取消済みの保存識別子を削除してログアウト状態にすることを検証します。
    ///
    /// 責務: revoked資格状態が安全な保存領域の無効セッション除去を要求することを確認します。
    func testRestoreRevokedIdentifierRemovesStoredSession() async throws {
        let authorization = AuthenticationAuthorizationPortFake()
        authorization.credentialState = .revoked
        let store = AuthenticationSessionStorePortFake(identifier: "revoked-user")
        let useCase = RestoreAuthenticationSessionUseCase(
            authorizationPort: authorization,
            sessionStore: store
        )

        let session = try await useCase.execute()

        XCTAssertNil(session)
        XCTAssertTrue(store.didRemoveIdentifier)
        XCTAssertNil(store.identifier)
    }

    /// Apple認証成功時にユーザー識別子を安全な保存境界へ渡すことを検証します。
    ///
    /// 責務: Apple認証結果が次回起動用セッションとして保存されることを確認します。
    func testSignInStoresAuthorizedUserIdentifier() async throws {
        let authorization = AuthenticationAuthorizationPortFake()
        authorization.authorizationSession = AppleAccountSession(userIdentifier: "signed-user")
        let store = AuthenticationSessionStorePortFake()
        let useCase = SignInWithAppleUseCase(
            authorizationPort: authorization,
            sessionStore: store
        )

        let session = try await useCase.execute()

        XCTAssertEqual(session.userIdentifier, "signed-user")
        XCTAssertEqual(store.identifier, "signed-user")
    }

    /// 空のAppleユーザー識別子を認証済みとして保存しないことを検証します。
    ///
    /// 責務: 不完全なApple認証結果がセッション確定前に拒否されることを確認します。
    func testSignInRejectsEmptyUserIdentifier() async {
        let authorization = AuthenticationAuthorizationPortFake()
        authorization.authorizationSession = AppleAccountSession(userIdentifier: "")
        let store = AuthenticationSessionStorePortFake()
        let useCase = SignInWithAppleUseCase(
            authorizationPort: authorization,
            sessionStore: store
        )

        do {
            _ = try await useCase.execute()
            XCTFail("空のAppleユーザー識別子が受理されました。")
        } catch let error as AppleAccountAuthorizationError {
            XCTAssertEqual(error, .failed)
        } catch {
            XCTFail("想定外のエラーです: \(error)")
        }
        XCTAssertNil(store.identifier)
    }

    /// アカウント削除が他端末失効をローカル消去より先に発行することを検証します。
    ///
    /// 責務: 削除処理の副作用順序が失効発行、データ消去、資格情報削除であることを確認します。
    func testDeleteAccountPublishesRevocationBeforeLocalErasure() async throws {
        let recorder = AuthenticationDeletionOrderRecorder()
        let useCase = DeleteAccountUseCase(
            sessionRevocation: AuthenticationDeletionRevocationPortFake(recorder: recorder),
            cloudErasers: AccountCloudDataErasers(
                sessionTransfers: AuthenticationDeletionTransferRepositoryFake(recorder: recorder),
                vehicleDataEraser: AuthenticationDeletionVehicleDataEraserFake(recorder: recorder),
                maintenanceDataEraser: AuthenticationDeletionMaintenanceDataEraserFake(recorder: recorder)
            ),
            dataEraser: AuthenticationDeletionDataEraserFake(recorder: recorder),
            sessionStore: AuthenticationDeletionSessionStoreFake(recorder: recorder)
        )

        try await useCase.execute(userIdentifier: "delete-user")

        XCTAssertEqual(recorder.events, [
            "delete-cloud-driving-data:delete-user",
            "delete-vehicle-data:delete-user",
            "delete-maintenance-data:delete-user",
            "publish:delete-user",
            "erase:delete-user",
            "remove-session"
        ])
    }

    /// CloudKit運転データを削除できない場合はローカルデータと資格情報を保持します。
    ///
    /// 責務: CloudKit全削除失敗が端末内削除を開始せずアカウント削除を再試行可能に保つことを確認します。
    func testDeleteAccountRetainsLocalDataWhenCloudDeletionFails() async {
        let recorder = AuthenticationDeletionOrderRecorder()
        let useCase = DeleteAccountUseCase(
            sessionRevocation: AuthenticationDeletionRevocationPortFake(recorder: recorder),
            cloudErasers: AccountCloudDataErasers(
                sessionTransfers: AuthenticationDeletionTransferRepositoryFake(
                    recorder: recorder,
                    deleteAllError: AuthenticationSessionStoreError.unavailable
                ),
                vehicleDataEraser: AuthenticationDeletionVehicleDataEraserFake(recorder: recorder),
                maintenanceDataEraser: AuthenticationDeletionMaintenanceDataEraserFake(recorder: recorder)
            ),
            dataEraser: AuthenticationDeletionDataEraserFake(recorder: recorder),
            sessionStore: AuthenticationDeletionSessionStoreFake(recorder: recorder)
        )

        do {
            try await useCase.execute(userIdentifier: "delete-user")
            XCTFail("CloudKit削除失敗後もアカウント削除が成功しました。")
        } catch {
            XCTAssertEqual(recorder.events, ["delete-cloud-driving-data:delete-user"])
        }
    }
}

/// 認証ユースケーステストでApple認証結果を制御します。
@MainActor
private final class AuthenticationAuthorizationPortFake: AppleAccountAuthorizationPort {
    /// `authorize`が返すセッションです。
    var authorizationSession = AppleAccountSession(userIdentifier: "user")

    /// 資格状態照会が返す状態です。
    var credentialState: AppleAccountCredentialState = .notFound

    /// 資格状態を照会されたユーザー識別子です。
    private(set) var requestedUserIdentifier: String?

    /// 資格状態照会の実行回数です。
    private(set) var credentialStateRequestCount = 0

    /// 設定されたAppleセッションを返します。
    ///
    /// 責務: テスト用Apple認証要求へ決定的なセッションを返します。
    /// - Returns: テストが設定したAppleアカウントセッション。
    func authorize() async throws -> AppleAccountSession {
        authorizationSession
    }

    /// 設定されたApple資格状態を返します。
    ///
    /// 責務: 資格照会入力を記録して決定的な資格状態を返します。
    /// - Parameter userIdentifier: ユースケースが照会したAppleユーザー識別子。
    /// - Returns: テストが設定したApple資格状態。
    func credentialState(for userIdentifier: String) async throws -> AppleAccountCredentialState {
        requestedUserIdentifier = userIdentifier
        credentialStateRequestCount += 1
        return credentialState
    }
}

/// 認証ユースケーステストで安全なセッション保存を記録します。
private final class AuthenticationSessionStorePortFake: AuthenticationSessionStorePort {
    /// 現在保存されているテスト用Appleユーザー識別子です。
    var identifier: String?

    /// セッション削除が要求されたかどうかです。
    private(set) var didRemoveIdentifier = false

    /// 初期保存識別子を指定してFakeを生成します。
    ///
    /// 責務: テスト用セッション保存境界を指定済み初期値へ設定します。
    /// - Parameter identifier: 初期状態で保存済みとするAppleユーザー識別子。
    init(identifier: String? = nil) {
        self.identifier = identifier
    }

    /// 現在のテスト用識別子を返します。
    ///
    /// 責務: テスト用保存領域から現在の認証セッション識別子を返します。
    /// - Returns: 現在保存されているテスト用識別子。
    func loadUserIdentifier() throws -> String? {
        identifier
    }

    /// テスト用識別子を置き換えます。
    ///
    /// 責務: ユースケースが保存した認証セッション識別子を記録します。
    /// - Parameter userIdentifier: 保存を要求されたAppleユーザー識別子。
    func saveUserIdentifier(_ userIdentifier: String) throws {
        identifier = userIdentifier
    }

    /// テスト用識別子を削除します。
    ///
    /// 責務: セッション削除要求を記録して保存済み識別子を除去します。
    func removeUserIdentifier() throws {
        didRemoveIdentifier = true
        identifier = nil
    }
}

/// アカウント削除ユースケースの副作用順序を記録します。
@MainActor
final class AuthenticationDeletionOrderRecorder {
    /// 発生順に保存したテスト用副作用名です。
    var events: [String] = []
}

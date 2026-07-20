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
            sessionTransfers: AuthenticationDeletionTransferRepositoryFake(recorder: recorder),
            vehicleDataEraser: AuthenticationDeletionVehicleDataEraserFake(recorder: recorder),
            dataEraser: AuthenticationDeletionDataEraserFake(recorder: recorder),
            sessionStore: AuthenticationDeletionSessionStoreFake(recorder: recorder)
        )

        try await useCase.execute(userIdentifier: "delete-user")

        XCTAssertEqual(recorder.events, [
            "publish:delete-user",
            "delete-cloud-driving-data:delete-user",
            "delete-vehicle-data:delete-user",
            "erase:delete-user",
            "remove-session"
        ])
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
private final class AuthenticationDeletionOrderRecorder {
    /// 発生順に保存したテスト用副作用名です。
    var events: [String] = []
}

/// アカウント削除テストで失効発行を記録します。
@MainActor
private final class AuthenticationDeletionRevocationPortFake: AccountSessionRevocationPort {
    /// 副作用順序の共有記録先です。
    private let recorder: AuthenticationDeletionOrderRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: 失効発行Fakeを1件の副作用順序記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: AuthenticationDeletionOrderRecorder) {
        self.recorder = recorder
    }

    /// このテストでは使用しないセッション基準登録を無視します。
    ///
    /// 責務: 削除順序テストに不要な基準登録境界を副作用なしで満たします。
    /// - Parameter userIdentifier: 使用しないユーザー識別子。
    func registerCurrentSession(for userIdentifier: String) {}

    /// 失効発行を共有履歴へ追加します。
    ///
    /// 責務: 1件の失効発行を順序検証可能なイベントへ変換します。
    /// - Parameter userIdentifier: 失効対象のユーザー識別子。
    func publishRevocation(for userIdentifier: String) {
        recorder.events.append("publish:\(userIdentifier)")
    }

    /// このテストでは使用しない失効監視を無視します。
    ///
    /// 責務: 削除順序テストに不要な監視境界を副作用なしで満たします。
    /// - Parameters:
    ///   - userIdentifier: 使用しないユーザー識別子。
    ///   - receive: 使用しない失効受信処理。
    func startObserving(
        for userIdentifier: String,
        receive: @escaping () -> Void
    ) {}

    /// このテストでは使用しない監視終了を無視します。
    ///
    /// 責務: 削除順序テストに不要な監視終了境界を副作用なしで満たします。
    func stopObserving() {}
}

/// アカウント削除テストでデータ消去を記録します。
@MainActor
private final class AuthenticationDeletionDataEraserFake: AccountDataErasurePort {
    /// 副作用順序の共有記録先です。
    private let recorder: AuthenticationDeletionOrderRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: データ消去Fakeを1件の副作用順序記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: AuthenticationDeletionOrderRecorder) {
        self.recorder = recorder
    }

    /// データ消去を共有履歴へ追加します。
    ///
    /// 責務: 1件のデータ消去を順序検証可能なイベントへ変換します。
    /// - Parameter userIdentifier: 消去対象のユーザー識別子。
    func eraseAllData(for userIdentifier: String) throws {
        recorder.events.append("erase:\(userIdentifier)")
    }
}

/// アカウント削除テストでCloudKit運転データ削除を記録します。
@MainActor
private final class AuthenticationDeletionTransferRepositoryFake: ConnectionSessionTransferRepository {
    /// 副作用順序の共有記録先です。
    private let recorder: AuthenticationDeletionOrderRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: CloudKit運転データ削除Fakeを1件の副作用順序記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: AuthenticationDeletionOrderRecorder) { self.recorder = recorder }

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

    /// CloudKit運転データ削除を共有履歴へ追加します。
    ///
    /// 責務: 1件のCloudKit全削除を順序検証可能なイベントへ変換します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func deleteAll(for accountIdentifier: String) async throws {
        recorder.events.append("delete-cloud-driving-data:\(accountIdentifier)")
    }
}

/// アカウント削除テストで車両カタログ削除を記録します。
@MainActor
private final class AuthenticationDeletionVehicleDataEraserFake: AccountVehicleDataErasurePort {
    /// 副作用順序の共有記録先です。
    private let recorder: AuthenticationDeletionOrderRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: 車両カタログ削除Fakeを1件の副作用順序記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: AuthenticationDeletionOrderRecorder) { self.recorder = recorder }

    /// 全保存先の車両カタログ削除を共有履歴へ追加します。
    ///
    /// 責務: 1件の車両データ全削除を順序検証可能なイベントへ変換します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func deleteAllVehicleData(for accountIdentifier: String) async throws {
        recorder.events.append("delete-vehicle-data:\(accountIdentifier)")
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

/// アカウント削除テストで資格情報削除を記録します。
@MainActor
private final class AuthenticationDeletionSessionStoreFake: AuthenticationSessionStorePort {
    /// 副作用順序の共有記録先です。
    private let recorder: AuthenticationDeletionOrderRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: 資格情報削除Fakeを1件の副作用順序記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: AuthenticationDeletionOrderRecorder) {
        self.recorder = recorder
    }

    /// このテストでは使用しない保存済み識別子を返します。
    ///
    /// 責務: 削除順序テストに不要な読込境界を未保存結果として満たします。
    /// - Returns: 常に `nil`。
    func loadUserIdentifier() throws -> String? { nil }

    /// このテストでは使用しない識別子保存を無視します。
    ///
    /// 責務: 削除順序テストに不要な保存境界を副作用なしで満たします。
    /// - Parameter userIdentifier: 使用しないユーザー識別子。
    func saveUserIdentifier(_ userIdentifier: String) throws {}

    /// 資格情報削除を共有履歴へ追加します。
    ///
    /// 責務: 1件の資格情報削除を順序検証可能なイベントへ変換します。
    func removeUserIdentifier() throws {
        recorder.events.append("remove-session")
    }
}

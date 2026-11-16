import XCTest
@testable import ProjectZD8

/// 対話的なサインインが、削除済みの印を解除してから識別子を保存することを仕様から検証します。
///
/// 仕様: authorize の後、`saveUserIdentifier` の前に `clearMarker` を呼ぶ。`clearMarker` が失敗したらサインインも失敗し、識別子は保存しない。
/// 復元(`RestoreAuthenticationSessionUseCase`)は印の依存を持たず、印に触れない。
@MainActor
final class SignInWithAppleUseCaseMarkerTests: XCTestCase {
    /// 検証用に失敗させるエラーです。
    private struct ClearFailure: Error, Equatable {}

    /// 成功時に、印の解除が識別子の保存より先に行われることを検証します。
    ///
    /// 責務: 解除 → 保存の順序と、解除対象が認可された識別子であることを確認します。
    func testSignInClearsMarkerBeforeSavingIdentifier() async throws {
        let log = SignInEventLog()
        let marker = AccountDeletionMarkerPortFake()
        marker.onClear = { log.events.append("clear:\($0)") }
        let store = SignInRecordingStoreFake(log: log)
        let useCase = SignInWithAppleUseCase(
            authorizationPort: SignInAuthorizationFake(userIdentifier: "signed-user"),
            sessionStore: store,
            deletionMarker: marker
        )

        let session = try await useCase.execute()

        XCTAssertEqual(session.userIdentifier, "signed-user")
        XCTAssertEqual(log.events, ["clear:signed-user", "save:signed-user"])
    }

    /// 印の解除が失敗したらサインインも失敗し、識別子を保存しないことを検証します。
    ///
    /// 責務: 解除失敗のエラーが伝わり、保存が1回も呼ばれないことを確認します。
    func testClearFailureFailsSignInWithoutSavingIdentifier() async {
        let log = SignInEventLog()
        let marker = AccountDeletionMarkerPortFake()
        marker.clearError = ClearFailure()
        let store = SignInRecordingStoreFake(log: log)
        let useCase = SignInWithAppleUseCase(
            authorizationPort: SignInAuthorizationFake(userIdentifier: "signed-user"),
            sessionStore: store,
            deletionMarker: marker
        )

        do {
            _ = try await useCase.execute()
            XCTFail("印の解除に失敗したのにサインインが成功しました。")
        } catch {
            XCTAssertEqual(error as? ClearFailure, ClearFailure())
        }

        XCTAssertEqual(marker.clearedAccounts, ["signed-user"])
        XCTAssertTrue(log.events.isEmpty)
    }

    /// 識別子が空の認可結果では、印の解除も保存もしないことを検証します。
    ///
    /// 責務: 不完全な認可結果で印へ触れないことを確認します。
    func testEmptyIdentifierNeitherClearsMarkerNorSaves() async {
        let log = SignInEventLog()
        let marker = AccountDeletionMarkerPortFake()
        let useCase = SignInWithAppleUseCase(
            authorizationPort: SignInAuthorizationFake(userIdentifier: ""),
            sessionStore: SignInRecordingStoreFake(log: log),
            deletionMarker: marker
        )

        do {
            _ = try await useCase.execute()
            XCTFail("空の識別子でサインインが成功しました。")
        } catch {
            XCTAssertEqual(error as? AppleAccountAuthorizationError, .failed)
        }

        XCTAssertTrue(marker.clearedAccounts.isEmpty)
        XCTAssertTrue(log.events.isEmpty)
    }
}

/// サインインの副作用の順序を記録します。
private final class SignInEventLog {
    /// 発生順の副作用名です。
    var events: [String] = []
}

/// 認可結果を固定するApple認証Fakeです。
@MainActor
private final class SignInAuthorizationFake: AppleAccountAuthorizationPort {
    /// 返す識別子です。
    private let userIdentifier: String

    /// 返す識別子を指定して生成します。
    ///
    /// 責務: 認可結果を1件の識別子へ固定します。
    /// - Parameter userIdentifier: 認可結果の識別子。
    init(userIdentifier: String) { self.userIdentifier = userIdentifier }

    /// 固定した認可結果を返します。
    ///
    /// 責務: 認可の成功を再現します。
    /// - Returns: 固定した識別子のセッション。
    func authorize() async throws -> AppleAccountSession { AppleAccountSession(userIdentifier: userIdentifier) }

    /// 使用しない資格状態照会です。
    ///
    /// 責務: 境界を満たすために固定値を返します。
    /// - Parameter _: 使用しない識別子。
    /// - Returns: 常に `.notFound`。
    func credentialState(for _: String) async throws -> AppleAccountCredentialState { .notFound }
}

/// 保存を共有履歴へ記録するセッション保存Fakeです。
private final class SignInRecordingStoreFake: AuthenticationSessionStorePort {
    /// 共有履歴です。
    private let log: SignInEventLog

    /// 共有履歴を注入します。
    ///
    /// 責務: 保存を履歴へ結び付けます。
    /// - Parameter log: 副作用の履歴。
    init(log: SignInEventLog) { self.log = log }

    /// 使用しない読込です。
    ///
    /// 責務: 境界を満たすために未保存を返します。
    /// - Returns: 常に `nil`。
    func loadUserIdentifier() throws -> String? { nil }

    /// 保存を履歴へ追加します。
    ///
    /// 責務: 識別子の保存を検証可能なイベントへ変換します。
    /// - Parameter userIdentifier: 保存する識別子。
    func saveUserIdentifier(_ userIdentifier: String) throws { log.events.append("save:\(userIdentifier)") }

    /// 使用しない削除です。
    ///
    /// 責務: 境界を満たします。
    func removeUserIdentifier() throws {
        // このテストでは呼び出しを観測しないため、何もしない。
    }
}

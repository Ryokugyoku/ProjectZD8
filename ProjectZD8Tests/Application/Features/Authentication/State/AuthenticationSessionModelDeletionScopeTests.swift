import XCTest
@testable import ProjectZD8

/// アカウント削除の開始時に、各機能が止まれるよう認証段階が変わることを検証します。
///
/// 現状 `AuthenticationSessionModel` は削除中も `phase == .signedIn` のままで、各モデルは
/// `AuthenticationAcquisitionEndPolicy` などで認証段階の変化(`.signedOut` など)を見て停止するため、停止の契機が無い。
/// 専用通知を実装する場合は、この検証を実装側の通知へ書き換える。
@MainActor
final class AuthenticationSessionModelDeletionScopeTests: XCTestCase {
    /// 待機の上限回数です。実時間は待たず `Task.yield()` だけを繰り返します。
    private static let maximumYields = 500

    /// クラウド削除が完了する前に、認証段階がサインイン済みでなくなることを検証します。
    ///
    /// 責務: 削除開始から完了までの間に、同期・保存・記録が止まれる契機が観測できることを確認します。
    func testPhaseLeavesSignedInWhileDeletionIsStillRunning() async {
        let gate = DeletionGateVehicleEraser()
        let session = AppleAccountSession(userIdentifier: "delete-user")
        let model = makeModel(gate: gate, session: session)
        defer { gate.release() }

        model.send(.accountDeletionRequested)
        model.send(.accountDeletionWarningConfirmed)
        model.send(.accountDeletionConfirmed)
        let reached = await waitUntil { gate.isWaiting }
        XCTAssertTrue(reached, "車両のクラウド削除に到達しませんでした(タイムアウト)。")

        XCTAssertEqual(model.state.accountDeletionPhase, .deleting)
        XCTAssertNotEqual(
            model.state.phase,
            .signedIn,
            "削除中も signedIn のままで、各機能が止まる契機がありません。"
        )
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

    /// 車両のクラウド削除を保留できるモデルを組み立てます。
    ///
    /// 責務: 既存Fakeと保留Fakeから、サインイン済みの認証モデルを生成します。
    /// - Parameters:
    ///   - gate: 車両のクラウド削除を保留するFake。
    ///   - session: 初期のサインイン済みセッション。
    /// - Returns: 検証対象のモデル。
    private func makeModel(
        gate: DeletionGateVehicleEraser,
        session: AppleAccountSession
    ) -> AuthenticationSessionModel {
        let authorization = AuthenticationModelAuthorizationPortFake()
        let store = AuthenticationModelSessionStorePortFake()
        let dataEraser = AuthenticationModelAccountDataEraserFake()
        let revocation = AuthenticationModelSessionRevocationPortFake()
        return AuthenticationSessionModel(
            state: AuthenticationState(phase: .signedIn, session: session),
            restoreSession: RestoreAuthenticationSessionUseCase(authorizationPort: authorization, sessionStore: store),
            signInWithApple: SignInWithAppleUseCase(authorizationPort: authorization, sessionStore: store),
            deleteAccount: DeleteAccountUseCase(
                sessionRevocation: revocation,
                cloudErasers: AccountCloudDataErasers(
                    sessionTransfers: AuthenticationModelTransferRepositoryFake(),
                    vehicleDataEraser: gate,
                    maintenanceDataEraser: AuthenticationModelMaintenanceDataEraserFake()
                ),
                dataEraser: dataEraser,
                sessionStore: store
            ),
            remoteAccountLogout: RemoteAccountLogoutUseCase(dataEraser: dataEraser, sessionStore: store),
            sessionRevocation: revocation
        )
    }
}

/// 車両のクラウド削除を `release()` まで保留するFakeです。
@MainActor
final class DeletionGateVehicleEraser: AccountVehicleDataErasurePort {
    /// 保留中の継続です。
    private var continuation: CheckedContinuation<Void, Never>?

    /// 解放済みかどうかです。解放後に到達した削除は保留しません。
    private var isReleased = false

    /// 削除が保留に入っているかどうかです。
    var isWaiting: Bool { continuation != nil }

    /// 保留を解いて削除を完了させます。
    ///
    /// 責務: テスト終了時に保留中のタスクを取り残さないようにします。
    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }

    /// 解放されるまで保留します。
    ///
    /// 責務: 削除の途中状態をテストが観測できるよう1回だけ待ちます。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    func deleteAllVehicleData(for accountIdentifier: String) async throws {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    /// 空の車両ID群を返します。
    ///
    /// 責務: このテストで対象外の照会を満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func localVehicleIDs(for accountIdentifier: String) -> [VehicleID] { [] }

    /// キャッシュ削除を受け流します。
    ///
    /// 責務: このテストで対象外の境界を満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    func removeLocalVehicleCache(for accountIdentifier: String) {}
}

/// アカウント削除に関わる認証セッションモデルの組み立てを、iOSとmacOSで共有します。
@MainActor
enum AccountDeletionComposition {
    /// 認証セッションモデルを生成し、削除済みの印の検出時に端末内ログアウトを結び付けます。
    ///
    /// 責務: サインイン・アカウント削除・リモートログアウトの各ユースケースへ共有の印と消去境界を配線し、検出時のログアウトを関門へ登録します。
    /// - Parameters:
    ///   - state: 認証セッションモデルの初期状態。
    ///   - authorization: Apple認証の境界。
    ///   - sessionStore: ログイン識別子の保存先。
    ///   - sessionRevocation: 端末間のセッション失効通知の境界。
    ///   - vehicleDataEraser: CloudKitと端末キャッシュの車両カタログを削除する境界。
    ///   - dataEraser: 端末内データを消去する境界。
    /// - Returns: 削除済みの印の検出と削除失敗の分類を結び付けた認証セッションモデル。
    static func makeAuthenticationSessionModel(
        state: AuthenticationState,
        authorization: any AppleAccountAuthorizationPort,
        sessionStore: any AuthenticationSessionStorePort,
        sessionRevocation: any AccountSessionRevocationPort,
        vehicleDataEraser: any AccountVehicleDataErasurePort,
        dataEraser: any AccountDataErasurePort
    ) -> AuthenticationSessionModel {
        let model = AuthenticationSessionModel(
            state: state,
            restoreSession: RestoreAuthenticationSessionUseCase(
                authorizationPort: authorization,
                sessionStore: sessionStore
            ),
            signInWithApple: SignInWithAppleUseCase(
                authorizationPort: authorization,
                sessionStore: sessionStore,
                deletionMarker: AccountDeletionMarkerComposition.marker
            ),
            deleteAccount: DeleteAccountUseCase(
                sessionRevocation: sessionRevocation,
                cloudErasers: AccountCloudDataErasers(
                    sessionTransfers: CloudKitConnectionSessionTransferRepository(),
                    vehicleDataEraser: vehicleDataEraser,
                    maintenanceDataEraser: CloudKitMaintenanceRemoteStore()
                ),
                dataEraser: dataEraser,
                sessionStore: sessionStore,
                deletionMarker: AccountDeletionMarkerComposition.marker,
                vehicleIDStore: UserDefaultsAccountDeletionVehicleIDStore()
            ),
            remoteAccountLogout: RemoteAccountLogoutUseCase(
                dataEraser: dataEraser,
                sessionStore: sessionStore
            ),
            sessionRevocation: sessionRevocation,
            deletionFailureClassifier: CloudKitAccountDeletionFailureClassifier()
        )
        AccountDeletionMarkerComposition.gate.onAccountDeleted = { [weak model] accountIdentifier in
            model?.applyRemoteSessionRevocation(for: accountIdentifier)
        }
        return model
    }
}

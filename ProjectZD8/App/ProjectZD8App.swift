import SwiftUI

/// ProjectZD8のプロセスエントリーポイントとプラットフォーム別ルート画面を構築します。
@main
struct ProjectZD8App: App {
    /// ルート画面の表示可否を決定する認証セッションモデルです。
    @State private var authenticationModel: AuthenticationSessionModel

    /// Connectionを除く設定をアカウント単位で保持するモデルです。
    @State private var accountSettingsModel: AccountSettingsModel

    /// 登録車両、VIN確認、CloudKit同期を保持するモデルです。
    @State private var vehicleManagementModel: VehicleManagementModel

    /// 主要PIDの1回読取り状態を保持するモデルです。
    @State private var liveTelemetryModel: LiveTelemetryModel

    #if os(iOS)
    /// iOS設定画面へ注入するプレゼンテーションモデルです。
    @State private var iOSSettingsModel: IOSSettingsPresentationModel
    #endif

    #if os(macOS)
    /// macOS設定画面へ注入するプレゼンテーションモデルです。
    @State private var macOSSettingsModel: MacOSSettingsPresentationModel
    #endif

    /// プラットフォーム固有の依存関係を組み立ててアプリを生成します。
    ///
    /// 責務: 現在のプラットフォーム用Compositionから認証、同期設定、Connection設定、車両管理の各モデルを構築します。
    init() {
        #if os(iOS)
        _authenticationModel = State(
            initialValue: IOSApplicationComposition.makeAuthenticationSessionModel()
        )
        _accountSettingsModel = State(
            initialValue: IOSApplicationComposition.makeAccountSettingsModel()
        )
        _iOSSettingsModel = State(
            initialValue: IOSApplicationComposition.makeSettingsPresentationModel()
        )
        _vehicleManagementModel = State(
            initialValue: IOSApplicationComposition.makeVehicleManagementModel()
        )
        _liveTelemetryModel = State(
            initialValue: IOSApplicationComposition.makeLiveTelemetryModel()
        )
        #endif

        #if os(macOS)
        _authenticationModel = State(
            initialValue: MacOSApplicationComposition.makeAuthenticationSessionModel()
        )
        _accountSettingsModel = State(
            initialValue: MacOSApplicationComposition.makeAccountSettingsModel()
        )
        _macOSSettingsModel = State(
            initialValue: MacOSApplicationComposition.makeSettingsPresentationModel()
        )
        _vehicleManagementModel = State(
            initialValue: MacOSApplicationComposition.makeVehicleManagementModel()
        )
        _liveTelemetryModel = State(
            initialValue: MacOSApplicationComposition.makeLiveTelemetryModel()
        )
        #endif
    }

    /// 現在のプラットフォームが所有するルート画面をアプリケーションウインドウへ配置します。
    ///
    /// 責務: 現在のAppleプラットフォームを独立したAppShellへ結び付けます。
    var body: some Scene {
        WindowGroup {
            Group {
#if os(iOS)
                if authenticationModel.state.phase == .signedIn {
                    IOSAppShellView(
                        accountSettingsModel: accountSettingsModel,
                        settingsModel: iOSSettingsModel,
                        vehicleManagementModel: vehicleManagementModel,
                        liveTelemetryModel: liveTelemetryModel,
                        accountDeletionPhase: authenticationModel.state.accountDeletionPhase,
                        accountDeletionFailure: authenticationModel.state.accountDeletionFailure,
                        sendAuthenticationAction: authenticationModel.send
                    )
                    .transition(.opacity)
                    .onAppear(perform: activateAuthenticatedSettingsScope)
                } else {
                    IOSLoginView(
                        state: authenticationModel.state,
                        send: authenticationModel.send
                    )
                    .transition(.opacity)
                }
#elseif os(macOS)
                if authenticationModel.state.phase == .signedIn {
                    MacOSAppShellView(
                        accountSettingsModel: accountSettingsModel,
                        settingsModel: macOSSettingsModel,
                        vehicleManagementModel: vehicleManagementModel,
                        liveTelemetryModel: liveTelemetryModel,
                        accountDeletionPhase: authenticationModel.state.accountDeletionPhase,
                        accountDeletionFailure: authenticationModel.state.accountDeletionFailure,
                        sendAuthenticationAction: authenticationModel.send
                    )
                    .transition(.opacity)
                    .onAppear(perform: activateAuthenticatedSettingsScope)
                } else {
                    MacOSLoginView(
                        state: authenticationModel.state,
                        send: authenticationModel.send
                    )
                    .transition(.opacity)
                }
#endif
            }
            .onChange(of: authenticationModel.state.phase) { _, phase in
                handleAuthenticationPhaseChange(phase)
            }
        }
    }

    /// 認証済みAppleユーザーをConnection以外の設定保存スコープへ反映します。
    ///
    /// 責務: 現在の認証セッション識別子をSettings機能へ1回通知します。
    private func activateAuthenticatedSettingsScope() {
        accountSettingsModel.send(
            .accountIdentifierChanged(authenticationModel.state.session?.userIdentifier)
        )
        vehicleManagementModel.send(
            .accountIdentifierChanged(authenticationModel.state.session?.userIdentifier)
        )
    }

    /// ログアウト状態へ変わったときに設定スコープと端末内表示状態を初期化します。
    ///
    /// 責務: 認証段階の変化をアカウント設定監視解除とプラットフォーム設定状態の再生成へ反映します。
    /// - Parameter phase: Authenticationが確定した新しい認証段階。
    private func handleAuthenticationPhaseChange(_ phase: AuthenticationPhase) {
        guard phase == .signedOut else { return }
        accountSettingsModel.send(.accountIdentifierChanged(nil))
        vehicleManagementModel.send(.accountIdentifierChanged(nil))
        #if os(iOS)
        iOSSettingsModel = IOSApplicationComposition.makeSettingsPresentationModel()
        #elseif os(macOS)
        macOSSettingsModel = MacOSApplicationComposition.makeSettingsPresentationModel()
        #endif
    }
}

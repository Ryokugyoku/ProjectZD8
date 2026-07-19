#if os(iOS)
import SwiftUI

/// iOSアプリケーション専用のルートレイアウトを描画します。
struct IOSAppShellView: View {
    /// iOSシェルが現在表示している遷移先です。
    @State private var selectedDestination: IOSAppShellDestination = .home

    /// 表示設定とBluetoothアダプター選択状態を画面操作へ変換するモデルです。
    let settingsModel: IOSSettingsPresentationModel

    /// 設定プレゼンテーションモデルを注入してiOSルート画面を生成します。
    ///
    /// 責務: iOS AppShellを単一の設定プレゼンテーションモデルへ結び付けます。
    /// - Parameter settingsModel: 表示設定とBluetooth候補選択状態を提供するモデル。
    init(settingsModel: IOSSettingsPresentationModel) {
        self.settingsModel = settingsModel
    }

    /// iPhone向けのコンテンツ領域と下部ナビゲーションを提供します。
    ///
    /// 責務: 選択中の遷移先と表示設定を使ってiOS AppShellを描画します。
    var body: some View {
        ZStack {
            IOSAppShellBackground()

            IOSDestinationView(
                destination: selectedDestination,
                settingsState: settingsModel.state,
                sendHomeAction: handleHomeAction,
                sendSettingsAction: settingsModel.send
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            IOSAppShellTabBar(selection: $selectedDestination)
        }
        .environment(\.locale, Locale(identifier: settingsModel.state.language.localeIdentifier))
        .preferredColorScheme(settingsModel.state.appearance.colorScheme)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-app-shell")
    }

    /// HOMEから受け取った1件の操作をiOSナビゲーションへ反映します。
    ///
    /// 責務: HOMEのアダプター設定要求を設定タブへの遷移と注目要求へ変換します。
    /// - Parameter action: HOMEから通知された型付き操作。
    private func handleHomeAction(_ action: IOSHomeAction) {
        switch action {
        case .adapterSetupRequested:
            selectedDestination = .settings
            settingsModel.send(.adapterAttentionRequested)
        }
    }
}
#endif

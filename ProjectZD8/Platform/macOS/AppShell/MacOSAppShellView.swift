#if os(macOS)
import SwiftUI

/// macOSアプリケーション専用のルートレイアウトを描画します。
struct MacOSAppShellView: View {
    /// macOSシェルが現在表示している遷移先です。
    @State private var selectedDestination: MacOSSidebarDestination = .home

    /// 表示設定とアダプター選択状態を画面操作へ変換するモデルです。
    let settingsModel: MacOSSettingsPresentationModel

    /// 設定プレゼンテーションモデルを注入してmacOSルート画面を生成します。
    ///
    /// 責務: macOS AppShellを単一の設定プレゼンテーションモデルへ結び付けます。
    /// - Parameter settingsModel: 表示設定とアダプター選択状態を提供するモデル。
    init(settingsModel: MacOSSettingsPresentationModel) {
        self.settingsModel = settingsModel
    }

    /// アプリケーション状態やインフラ状態を所有しないレスポンシブなmacOSシェルを提供します。
    ///
    /// 責務: 現在のウインドウ寸法と選択中の遷移先を使ってmacOS AppShellを描画します。
    var body: some View {
        GeometryReader { proxy in
            let metrics = MacOSAppShellMetrics.resolve(for: proxy.size)

            HStack(spacing: 0) {
                MacOSSidebarView(
                    selection: $selectedDestination,
                    metrics: metrics
                )

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)

                MacOSDestinationView(
                    destination: selectedDestination,
                    metrics: metrics,
                    settingsState: settingsModel.state,
                    sendSettingsAction: settingsModel.send
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-app-shell")
        .frame(minWidth: 640, minHeight: 420)
        .environment(\.locale, Locale(identifier: settingsModel.state.language.localeIdentifier))
        .preferredColorScheme(settingsModel.state.appearance.colorScheme)
    }
}
#endif

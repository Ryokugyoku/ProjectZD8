#if os(macOS)
import SwiftUI

/// macOSアプリケーション専用のルートレイアウトを描画します。
struct MacOSAppShellView: View {
    /// macOSシェルが現在表示している遷移先です。
    @State private var selectedDestination: MacOSSidebarDestination = .home

    /// AppShellが現在適用している表示設定です。
    @State private var settingsState = MacOSSettingsState()

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
                    settingsState: settingsState,
                    sendSettingsAction: handleSettingsAction
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-app-shell")
        .frame(minWidth: 640, minHeight: 420)
        .environment(\.locale, Locale(identifier: settingsState.language.localeIdentifier))
        .preferredColorScheme(settingsState.appearance.colorScheme)
    }

    /// 設定画面から受け取った表示設定操作をAppShellへ反映します。
    ///
    /// 責務: 1件の表示設定操作を現在のmacOS表示状態へ反映します。
    /// - Parameter action: 設定画面で選択された表示設定操作。
    private func handleSettingsAction(_ action: MacOSSettingsAction) {
        switch action {
        case let .languageSelected(language):
            settingsState.language = language
        case let .appearanceSelected(appearance):
            settingsState.appearance = appearance
        }
    }
}

#Preview {
    MacOSAppShellView()
        .frame(width: 1_200, height: 800)
}
#endif

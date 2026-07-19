#if os(macOS)
import SwiftUI

/// 選択されたmacOS遷移先に対応する画面を描画します。
struct MacOSDestinationView: View {
    /// この画面が表す遷移先です。
    let destination: MacOSSidebarDestination

    /// 現在のウインドウサイズに対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// 設定画面へ渡す現在の表示設定です。
    let settingsState: MacOSSettingsState

    /// 設定画面の操作をAppShellへ通知するクロージャです。
    let sendSettingsAction: (MacOSSettingsAction) -> Void

    /// 選択された遷移先に対応するmacOS画面を提供します。
    ///
    /// 責務: 現在の遷移先を専用画面または識別用プレースホルダーへ振り分けます。
    @ViewBuilder
    var body: some View {
        if destination == .settings {
            MacOSSettingsView(
                state: settingsState,
                send: sendSettingsAction,
                metrics: metrics
            )
        } else {
            placeholder
        }
    }

    /// 未実装の遷移先を識別できるプレースホルダーです。
    private var placeholder: some View {
        VStack(spacing: 22 * metrics.scale) {
            Image(systemName: destination.systemImage)
                .font(.system(size: metrics.contentSymbolSize, weight: .medium))
                .foregroundStyle(.tint)

            Text(destination.title)
                .font(.system(size: metrics.contentTitleSize, weight: .bold))

            Text("shell.destination.placeholder")
                .font(.system(size: 15 * metrics.scale))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(32 * metrics.scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("macos-destination-\(destination.rawValue)")
    }
}
#endif

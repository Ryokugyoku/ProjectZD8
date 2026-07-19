#if os(macOS)
import SwiftUI

/// 選択されたmacOS遷移先のプレゼンテーション専用プレースホルダーを描画します。
struct MacOSDestinationView: View {
    /// このプレースホルダーが表す遷移先です。
    let destination: MacOSSidebarDestination

    /// 現在のウインドウサイズに対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// ウインドウに合わせて内容が拡縮する遷移先領域を提供します。
    ///
    /// 責務: 機能ワークフローを実装せず、選択された遷移先の識別情報だけを描画します。
    var body: some View {
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

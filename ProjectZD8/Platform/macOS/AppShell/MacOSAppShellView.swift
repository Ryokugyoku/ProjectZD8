#if os(macOS)
import SwiftUI

/// macOSアプリケーション専用のルートレイアウトを描画します。
struct MacOSAppShellView: View {
    /// macOSシェルが現在表示している遷移先です。
    @State private var selectedDestination: MacOSSidebarDestination = .home

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
                    metrics: metrics
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-app-shell")
        .frame(minWidth: 640, minHeight: 420)
    }
}

#Preview {
    MacOSAppShellView()
        .frame(width: 1_200, height: 800)
}
#endif

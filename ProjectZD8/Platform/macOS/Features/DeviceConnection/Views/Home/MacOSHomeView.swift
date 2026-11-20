#if os(macOS)
import SwiftUI

/// macOSホームの画面ルートです。未接続時はアダプターの接続準備を、接続中は車両と記録の見出しとリアルタイム表示を並べます。
///
/// リアルタイム表示は LiveTelemetry の画面部品を名指しせず、差し込み口として受け取ります。
struct MacOSHomeView<LiveTelemetryPanel: View>: View {
    /// ホームに表示する状態です。
    let state: MacOSHomeState
    /// ホームの操作をAppShellへ通知するクロージャです。
    let send: (MacOSHomeAction) -> Void
    /// 現在のウインドウサイズに対応する表示寸法です。
    let metrics: MacOSAppShellMetrics
    /// AppShellが差し込むリアルタイム表示パネルです。
    private let liveTelemetryPanel: LiveTelemetryPanel

    /// 表示状態、操作の通知先、表示寸法、差し込むパネルを受け取ります。
    ///
    /// 責務: ホームの画面ルートを、状態と操作の通知先と表示寸法とパネルの差し込み口へ結び付けます。
    /// - Parameters:
    ///   - state: ホームに表示する状態。
    ///   - send: ホームの操作の通知先。
    ///   - metrics: 現在のウインドウサイズに対応する表示寸法。
    ///   - liveTelemetryPanel: 未接続・接続中のどちらの配置にも出すリアルタイム表示パネル。
    init(
        state: MacOSHomeState,
        send: @escaping (MacOSHomeAction) -> Void,
        metrics: MacOSAppShellMetrics,
        @ViewBuilder liveTelemetryPanel: () -> LiveTelemetryPanel
    ) {
        self.state = state
        self.send = send
        self.metrics = metrics
        self.liveTelemetryPanel = liveTelemetryPanel()
    }

    /// 配置の種類に応じて部品を縦に並べます。
    ///
    /// 責務: ホームの配置を切り替え、部品の操作をホームの操作へ変換します。
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26 * metrics.scale) {
                    switch state.screen.layout {
                    case .adapterSetup:
                        adapterSetupContent(isCompact: proxy.size.width < 720)
                    case .connectedSession:
                        connectedSessionContent
                    }
                }
                .padding(.horizontal, 34 * metrics.scale)
                .padding(.vertical, 32 * metrics.scale)
                .frame(maxWidth: 1_260 * metrics.scale, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
            .background(homeBackground)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-home-screen")
    }

    /// 未接続時の配置です。見出し、パネル(失敗や終了理由のバナー)、アダプターカードの順に並べます。
    ///
    /// 責務: 未接続時の部品を並べ、アダプターカードの操作をホームの操作へ変換します。
    /// - Parameter isCompact: アダプターカードの内部を縦方向へ並べる必要があるかどうか。
    /// - Returns: 未接続時の部品の並び。
    @ViewBuilder
    private func adapterSetupContent(isCompact: Bool) -> some View {
        MacOSHomeHeading(scale: metrics.scale)
        liveTelemetryPanel
        MacOSHomeAdapterCard(
            content: state.screen.adapterCard,
            isCompact: isCompact,
            scale: metrics.scale,
            onConnect: { send(.vehicleConnectionRequested($0)) },
            onSetupAdapter: { send(.adapterSetupRequested) }
        )
    }

    /// 接続中の配置です。セッション見出しのすぐ下に主要値から始まるパネルを並べます。
    @ViewBuilder
    private var connectedSessionContent: some View {
        if let sessionHeader = state.screen.sessionHeader {
            MacOSHomeSessionHeader(content: sessionHeader, scale: metrics.scale) {
                send(.vehicleDisconnectionRequested)
            }
        }
        liveTelemetryPanel
    }

    /// ホーム全体へ静かな奥行きを与える背景です。
    private var homeBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), Color.clear],
                startPoint: .topTrailing,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}
#endif

#if os(iOS)
import SwiftUI

/// iOSホームの画面ルートです。未接続時はアダプターの接続準備を、接続中は車両と記録の見出しとリアルタイム表示を並べます。
///
/// リアルタイム表示は LiveTelemetry の画面部品を名指しせず、差し込み口として受け取ります。
struct IOSHomeView<LiveTelemetryPanel: View>: View {
    /// ホームに表示する状態です。
    let state: IOSHomeState
    /// ホームの操作をAppShellへ通知するクロージャです。
    let send: (IOSHomeAction) -> Void
    /// AppShellが差し込むリアルタイム表示パネルです。
    private let liveTelemetryPanel: LiveTelemetryPanel

    /// 現在のDynamic Type設定です。
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 表示状態、操作の通知先、差し込むパネルを受け取ります。
    ///
    /// 責務: ホームの画面ルートを、状態と操作の通知先とパネルの差し込み口へ結び付けます。
    /// - Parameters:
    ///   - state: ホームに表示する状態。
    ///   - send: ホームの操作の通知先。
    ///   - liveTelemetryPanel: 未接続・接続中のどちらの配置にも出すリアルタイム表示パネル。
    init(
        state: IOSHomeState,
        send: @escaping (IOSHomeAction) -> Void,
        @ViewBuilder liveTelemetryPanel: () -> LiveTelemetryPanel
    ) {
        self.state = state
        self.send = send
        self.liveTelemetryPanel = liveTelemetryPanel()
    }

    /// 配置の種類に応じて部品を縦に並べます。パネルの分類詳細へ進めるようナビゲーションを持ちます。
    ///
    /// 責務: ホームの配置を切り替え、部品の操作をホームの操作へ変換します。
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: IOSHomeMetrics.sectionSpacing) {
                    switch state.screen.layout {
                    case .adapterSetup:
                        adapterSetupContent
                    case .connectedSession:
                        connectedSessionContent
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, IOSHomeMetrics.topPadding)
                .padding(.bottom, IOSHomeMetrics.bottomPadding)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-home-screen")
    }

    /// 未接続時の配置です。ブランド、見出し、パネル(失敗や終了理由のバナー)、アダプターカードの順に並べます。
    @ViewBuilder
    private var adapterSetupContent: some View {
        IOSHomeBrandHeader()
        IOSHomeHeading()
        liveTelemetryPanel
        IOSHomeAdapterCard(
            content: state.screen.adapterCard,
            onConnect: { send(.vehicleConnectionRequested($0)) },
            onSetupAdapter: { send(.adapterSetupRequested) }
        )
    }

    /// 接続中の配置です。セッション見出しのすぐ下に主要値から始まるパネルを並べます。
    @ViewBuilder
    private var connectedSessionContent: some View {
        if let sessionHeader = state.screen.sessionHeader {
            IOSHomeSessionHeader(content: sessionHeader) {
                send(.vehicleDisconnectionRequested)
            }
        }
        liveTelemetryPanel
    }

    /// 文字サイズに応じた左右の余白です。
    private var horizontalPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? IOSHomeMetrics.accessibilityHorizontalPadding : IOSHomeMetrics.horizontalPadding
    }
}
#endif

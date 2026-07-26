#if os(iOS)
import SwiftUI

/// iPhoneのSafe Areaへ追従するAppShell下部ナビゲーションを提供します。
struct IOSAppShellTabBar<DestinationContent: View>: View {
    /// 選択中の遷移先をiOS AppShellと共有します。
    @Binding var selection: IOSAppShellDestination

    /// 各タブに対応する画面を生成します。
    private let destinationContent: (IOSAppShellDestination) -> DestinationContent

    /// 選択状態と各遷移先の画面生成処理を受け取ります。
    ///
    /// 責務: iOS AppShellの選択状態とタブ別画面をシステムナビゲーションへ接続します。
    /// - Parameters:
    ///   - selection: 選択中の遷移先を読み書きするバインディング。
    ///   - destinationContent: 指定された遷移先に対応する画面を返す処理。
    init(
        selection: Binding<IOSAppShellDestination>,
        @ViewBuilder destinationContent: @escaping (IOSAppShellDestination) -> DestinationContent
    ) {
        _selection = selection
        self.destinationContent = destinationContent
    }

    /// 6件の遷移先をSafe Area対応のシステムタブとして提供します。
    ///
    /// 責務: iOS標準タブの配置規則でコンテンツとナビゲーションの占有領域を分離します。
    var body: some View {
        TabView(selection: $selection) {
            ForEach(IOSAppShellDestination.allCases) { destination in
                destinationContent(destination)
                    .tabItem {
                        Label(destination.compactTitle, systemImage: destination.systemImage)
                            .accessibilityIdentifier("ios-tab-\(destination.rawValue)")
                    }
                    .tag(destination)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-tab-bar")
    }
}
#endif

#if os(macOS)
import SwiftUI

/// macOS用の依存と画面間で共有する状態を保持します。
@MainActor
final class MacOSApplicationComposition {
    let core: AppComposition
    /// シェルとメニューコマンドが共有する選択状態です。
    let navigation = MacOSNavigationState()

    /// 責務: macOSのデバイス実装を使って依存を組み立てます。
    /// - Throws: データベースを準備できない場合のエラー。
    init() throws {
        core = try AppComposition(
            discovery: MacOSAdapterDiscovery(),
            sleepInhibitor: MacOSSystemSleepInhibitor(),
            defaultLocalRawRetention: .unlimited
        )
    }
}
#endif

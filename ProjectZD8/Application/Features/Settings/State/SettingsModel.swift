import Observation

/// アプリ設定の表示と変更を `AppSettingsStorePort` へ結び付けます。
@MainActor
@Observable
final class SettingsModel {
    /// 画面が描画する現在状態です。
    private(set) var state: SettingsState

    /// 設定が実際に変わるたびに、新しい設定を渡して呼ばれます。他のモデルや合成が現在の設定を受け取るために使います。
    @ObservationIgnored var onChange: (@MainActor (AppSettings) -> Void)?

    @ObservationIgnored private let store: any AppSettingsStorePort

    /// 保存先とAbout表示値を注入してモデルを生成し、保存済みの設定を読み込みます。
    ///
    /// 責務: 設定画面の状態を保存先へ結び付けます。
    init(store: any AppSettingsStorePort, appVersion: String, appBuild: String) {
        self.store = store
        state = SettingsState(settings: store.load(), appVersion: appVersion, appBuild: appBuild)
    }

    /// 現在の設定です。
    var settings: AppSettings { state.settings }

    /// 1件の操作を設定へ反映します。
    ///
    /// 責務: 変更を保存し、実際に変わった場合だけ `onChange` へ通知します。
    func send(_ action: SettingsAction) {
        var updated = state.settings
        switch action {
        case let .appearanceChanged(value): updated.appearance = value
        case let .demoModeChanged(value): updated.isDemoModeEnabled = value
        case let .localRawRetentionChanged(value): updated.localRawRetention = value
        case .reloadRequested: updated = store.load()
        }
        guard updated != state.settings else { return }
        if case .reloadRequested = action {} else { store.save(updated) }
        state.settings = updated
        onChange?(updated)
    }
}

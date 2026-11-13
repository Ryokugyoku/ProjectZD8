#if os(macOS)
import Observation

/// シェルとメニューコマンドが共有するナビゲーション状態。
///
/// 選択中の遷移先と、アダプター選択シートの表示状態だけを持つ(業務状態は持たない)。
@MainActor
@Observable
final class MacOSNavigationState {
    /// 現在選択中の遷移先。
    var selection: MacOSDestination
    /// アダプター選択シートを表示するか。
    var isAdapterPickerPresented = false

    /// 責務: 初期の遷移先を決めて状態を作る。
    init(selection: MacOSDestination = .drive) {
        self.selection = selection
    }

    /// 責務: 既定アダプターがあればそれで接続を要求し、無ければアダプター選択シートを開く。
    func requestConnection(deviceConnection: DeviceConnectionModel, driveSession: DriveSessionModel) {
        guard driveSession.state.phase.isIdle else { return }
        selection = .drive
        if let adapter = deviceConnection.state.defaultAdapter {
            driveSession.send(.connectRequested(adapter))
        } else {
            isAdapterPickerPresented = true
        }
    }
}
#endif

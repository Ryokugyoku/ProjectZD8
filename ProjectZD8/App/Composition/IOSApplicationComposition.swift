#if os(iOS)
import SwiftUI

/// iOS用の依存を保持し、既定アダプターの出現監視を管理します。
@MainActor
final class IOSApplicationComposition {
    let core: AppComposition
    private let arrivalMonitor: IOSAdapterArrivalMonitor

    /// 責務: iOSのデバイス実装を使って依存を組み立てます。通知応答を取りこぼさないよう起動完了前に呼びます。
    /// - Throws: データベースを準備できない場合のエラー。
    init() throws {
        arrivalMonitor = IOSAdapterArrivalMonitor(notifier: IOSAdapterArrivalNotifier())
        core = try AppComposition(
            discovery: IOSAdapterDiscovery(externalAccessoryConfiguration: IOSExternalAccessoryProtocolConfiguration()),
            sleepInhibitor: IOSScreenSleepInhibitor(),
            defaultLocalRawRetention: .days90
        )
    }

    /// 責務: 既定アダプターがBLEなら出現監視を始め、そうでなければ止めます。
    func updateArrivalMonitoring(for adapter: AdapterDescriptor?) {
        arrivalMonitor.stopMonitoring()
        guard let adapter, adapter.transport == .bluetoothLowEnergy else { return }
        let deviceConnection = core.deviceConnection
        arrivalMonitor.startMonitoring(adapter) { deviceConnection.acceptArrival($0) }
    }
}
#endif

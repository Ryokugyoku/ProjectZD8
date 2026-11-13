#if os(iOS) || os(macOS)
import Foundation

/// CoreBluetoothでAppleデバイス周辺のBLEアダプターを一定時間探索します。
nonisolated struct AppleCoreBluetoothAdapterDiscovery: AdapterDiscoveryPort {
    /// 探索実装を生成します。
    ///
    /// 責務: 状態を持たないBLE探索境界を構築します。探索ごとに新しいスキャンを開始します。
    init() {}

    /// 責務: 10秒間のBLEスキャンを1回実行し、既知OBD候補だけを返します。
    /// - Throws: Bluetoothの電源・権限・対応状況に応じた `AdapterDiscoveryError`、またはタスク取消し。
    func discoverAdapters() async throws -> [AdapterDescriptor] {
        try await Self.scan()
    }

    /// 責務: MainActor上で1回分のスキャンセッションを生成して実行します。
    @MainActor
    private static func scan() async throws -> [AdapterDescriptor] {
        try await AppleCoreBluetoothScan().run()
    }
}
#endif

#if os(macOS)
import Foundation

/// Bluetooth Classicの履歴と周辺探索からペアリング済みOBDLink MX+だけを取得します。
nonisolated struct MacOSBluetoothClassicAdapterDiscovery: AdapterDiscoveryPort {
    /// 探索実装を生成します。
    ///
    /// 責務: 状態を持たないBluetooth Classic探索境界を構築します。探索ごとに新しいスキャンを開始します。
    init() {}

    /// 責務: 最近参照した機器と5秒間の周辺探索からMX+候補を返します。
    /// - Throws: 探索を開始できない場合は `AdapterDiscoveryError.failed`、またはタスク取消し。
    func discoverAdapters() async throws -> [AdapterDescriptor] {
        try await Self.scan()
    }

    /// 責務: MainActor上で1回分のスキャンセッションを生成して実行します。
    @MainActor
    private static func scan() async throws -> [AdapterDescriptor] {
        try await MacOSBluetoothClassicScan().run()
    }
}
#endif

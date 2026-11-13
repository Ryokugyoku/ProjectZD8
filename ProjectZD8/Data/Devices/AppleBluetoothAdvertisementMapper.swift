#if os(iOS) || os(macOS)
import Foundation

/// AppleプラットフォームのBluetooth Low Energy検出値をDomain候補へ変換します。
struct AppleBluetoothAdvertisementMapper {
    /// CoreBluetoothから取得した1件の検出値をアダプター候補へ変換します。
    ///
    /// 責務: Advertisement Local Name、周辺機器名、UUIDの優先順で1件のBLE候補を構築します。
    /// - Parameters:
    ///   - peripheralIdentifier: CoreBluetoothが周辺機器へ割り当てたUUID。
    ///   - advertisementLocalName: アドバタイズメントから取得したローカル名称。
    ///   - peripheralName: `CBPeripheral` から取得した名称。
    ///   - connectionState: 検出時点の周辺機器接続状態。
    ///   - hasManufacturerData: アドバタイズメントにManufacturer Dataが含まれていたかどうか。
    ///   - serviceIdentifiers: アドバタイズメントから取得したService UUID一覧。
    /// - Returns: Manufacturer Dataのバイト列を名称へ変換しないBluetooth候補。
    func makeAdapter(
        peripheralIdentifier: UUID,
        advertisementLocalName: String?,
        peripheralName: String?,
        connectionState: DiscoveredAdapterConnectionState,
        hasManufacturerData: Bool,
        serviceIdentifiers: [String] = []
    ) -> DiscoveredAdapter {
        let identifier = peripheralIdentifier.uuidString
        let localName = normalized(advertisementLocalName)
        let systemName = normalized(peripheralName)
        let displayName = localName ?? systemName ?? identifier

        return DiscoveredAdapter(
            id: "bluetooth-low-energy:\(identifier)",
            transportMode: .bluetooth,
            displayName: displayName,
            productName: systemName,
            advertisementLocalName: localName,
            hasManufacturerData: hasManufacturerData,
            bluetoothServiceIdentifiers: serviceIdentifiers
                .map { $0.uppercased() }
                .uniqued()
                .sorted(),
            systemIdentifier: identifier,
            isConnected: connectionState == .connected,
            connectionState: connectionState
        )
    }

    /// 空白だけのシステム名称を取得不能として正規化します。
    ///
    /// 責務: 1件の任意名称から表示可能な非空文字列だけを返します。
    /// - Parameter value: CoreBluetoothから取得した任意名称。
    /// - Returns: 前後の空白を除いた名称。空または取得不能の場合は `nil`。
    private func normalized(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }
        return normalized
    }
}

/// Hashable値の入力順を保った重複除外を提供します。
private extension Sequence where Element: Hashable {
    /// 入力順で初出した要素だけを返します。
    ///
    /// 責務: 1件のSequenceを入力順を維持した重複なし配列へ縮約します。
    /// - Returns: 初出順の重複なし要素配列。
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
#endif

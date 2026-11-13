import Foundation

/// BLE検出値を `AdapterDescriptor` へ変換します。
nonisolated struct AppleBluetoothAdvertisementMapper: Sendable {
    /// BLE検出値1件を探索結果の記述へ変換します。
    ///
    /// 責務: ローカル名、周辺機器名、UUIDの優先順で表示名を決めて1件のBLEアダプター記述を構築します。
    /// - Parameter advertisement: CoreBluetoothの検出値。
    /// - Returns: Manufacturer Dataを名称へ変換しないBLEアダプター記述。
    func makeAdapter(from advertisement: BluetoothAdvertisement) -> AdapterDescriptor {
        let identifier = advertisement.peripheralIdentifier.uuidString
        let localName = normalized(advertisement.localName)
        let systemName = normalized(advertisement.peripheralName)
        let displayName = localName ?? systemName ?? identifier
        return AdapterDescriptor(
            transport: .bluetoothLowEnergy,
            systemIdentifier: identifier,
            displayName: displayName,
            detail: systemName == displayName ? nil : systemName
        )
    }

    /// 空白だけの名称を取得不能として正規化します。
    ///
    /// 責務: 1件の任意名称から表示可能な非空文字列だけを返します。
    private func normalized(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else { return nil }
        return normalized
    }
}

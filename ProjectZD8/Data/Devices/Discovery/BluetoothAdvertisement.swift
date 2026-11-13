import Foundation

/// CoreBluetoothが報告したBLE周辺機器1件の検出値です。フレームワーク型を持ちません。
nonisolated struct BluetoothAdvertisement: Equatable, Sendable {
    /// CoreBluetoothが周辺機器へ割り当てたUUIDです。
    let peripheralIdentifier: UUID
    /// アドバタイズメントのローカル名です。
    let localName: String?
    /// `CBPeripheral` が持つ名称です。
    let peripheralName: String?
    /// アドバタイズメントのService UUID文字列です(通常とOverflowの合算)。
    let serviceIdentifiers: [String]

    /// 検出値を生成します。
    ///
    /// 責務: 1件のBLE検出値を値型へまとめます。
    init(peripheralIdentifier: UUID, localName: String?, peripheralName: String?, serviceIdentifiers: [String] = []) {
        self.peripheralIdentifier = peripheralIdentifier
        self.localName = localName
        self.peripheralName = peripheralName
        self.serviceIdentifiers = serviceIdentifiers
    }
}

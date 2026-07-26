#if os(iOS) || os(macOS)
import Foundation

/// AppleプラットフォームのBLE探索結果を既知のOBDアダプター信号へ限定する判定規則です。
nonisolated struct AppleOBDBluetoothCandidatePolicy: Sendable {
    /// 公式製品資料または採用済み参照実装で確認したBLE表示名の接頭辞です。
    private static let knownNamePrefixes = [
        "OBDLINK",
        "VEEPEAK",
        "VGATE",
        "IOS-VLINK"
    ]

    /// 通信実装が明示的に扱う既知UART Service UUIDです。
    private static let knownServiceIdentifiers = Set(
        AppleBluetoothUARTProfile.supported.map(\.serviceUUID)
    )

    /// 1件のBLE候補が既知のOBD表示名またはUART Service UUIDを持つか判定します。
    ///
    /// 責務: 1件のBLE探索候補をユーザーへ提示可能な既知OBD候補かどうかへ分類します。
    /// - Parameter adapter: CoreBluetooth広告から構築したBLE候補。
    /// - Returns: 既知名称または既知UART Service UUIDに一致する場合は `true`。
    func accepts(_ adapter: DiscoveredAdapter) -> Bool {
        let names = [
            adapter.advertisementLocalName,
            adapter.productName,
            adapter.displayName
        ]
        if names.compactMap({ $0 }).contains(where: isKnownName) {
            return true
        }
        return !Self.knownServiceIdentifiers.isDisjoint(
            with: adapter.bluetoothServiceIdentifiers.map { $0.uppercased() }
        )
    }

    /// 1件の表示名が既知OBD製品の名称接頭辞を持つか判定します。
    ///
    /// 責務: 1件の任意表示名を大文字化して既知OBD名称集合と照合します。
    /// - Parameter name: BLE広告またはPeripheralから取得した表示名。
    /// - Returns: 既知名称接頭辞に一致する場合は `true`。
    private func isKnownName(_ name: String) -> Bool {
        let normalized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return Self.knownNamePrefixes.contains(where: normalized.hasPrefix)
    }
}
#endif

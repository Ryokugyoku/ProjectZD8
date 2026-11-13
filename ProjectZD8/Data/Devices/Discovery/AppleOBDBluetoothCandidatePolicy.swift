#if os(iOS) || os(macOS)
import Foundation

/// BLE探索結果を既知のOBDアダプター信号へ限定する判定規則です。
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

    /// 1件のBLE検出値が既知のOBD表示名またはUART Service UUIDを持つか判定します。
    ///
    /// 責務: 1件のBLE検出値をユーザーへ提示可能な既知OBD候補かどうかへ分類します。
    /// - Parameter advertisement: CoreBluetoothの検出値。
    /// - Returns: 既知名称または既知UART Service UUIDに一致する場合は `true`。
    func accepts(_ advertisement: BluetoothAdvertisement) -> Bool {
        let names = [advertisement.localName, advertisement.peripheralName]
        if names.compactMap({ $0 }).contains(where: isKnownName) {
            return true
        }
        return !Self.knownServiceIdentifiers.isDisjoint(
            with: advertisement.serviceIdentifiers.map { $0.uppercased() }
        )
    }

    /// 1件の表示名が既知OBD製品の名称接頭辞を持つか判定します。
    ///
    /// 責務: 1件の任意表示名を大文字化して既知OBD名称集合と照合します。
    private func isKnownName(_ name: String) -> Bool {
        let normalized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return Self.knownNamePrefixes.contains(where: normalized.hasPrefix)
    }
}
#endif

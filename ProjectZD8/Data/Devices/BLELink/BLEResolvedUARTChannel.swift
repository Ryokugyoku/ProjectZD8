#if os(iOS) || os(macOS)
/// 実機の能力から確定した送受信用のUART Characteristicと書き込み種別です。
nonisolated struct BLEResolvedUARTChannel: Equatable, Sendable {
    /// UARTを公開するService UUIDです。
    let serviceUUID: String
    /// 通知を受けるCharacteristic UUIDです。
    let notifyCharacteristicUUID: String
    /// 書き込むCharacteristic UUIDです。
    let writeCharacteristicUUID: String
    /// 書き込みに使う種別です。
    let writeKind: BLEWriteKind

    /// 解決済みUART構成と書き込みCharacteristic能力から送受信路を生成します。
    ///
    /// 責務: 応答なし書き込みが使えればそれを、なければ応答ありを選んで送受信路を固定します。
    /// - Parameters:
    ///   - profile: 解決済みのUART構成。
    ///   - writeCapability: 書き込みCharacteristicの能力。
    /// - Returns: 書き込み可能な送受信路。書き込み能力がなければ `nil`。
    static func make(
        profile: AppleBluetoothUARTProfile,
        writeCapability: AppleBluetoothCharacteristicCapability
    ) -> BLEResolvedUARTChannel? {
        let kind: BLEWriteKind
        if writeCapability.supportsWriteWithoutResponse {
            kind = .withoutResponse
        } else if writeCapability.supportsWriteWithResponse {
            kind = .withResponse
        } else {
            return nil
        }
        return BLEResolvedUARTChannel(
            serviceUUID: profile.serviceUUID,
            notifyCharacteristicUUID: profile.notifyCharacteristicUUID,
            writeCharacteristicUUID: profile.writeCharacteristicUUID,
            writeKind: kind
        )
    }
}
#endif

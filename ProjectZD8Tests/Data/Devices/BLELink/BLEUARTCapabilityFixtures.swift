@testable import ProjectZD8

/// 既知UART構成(FFF0: write FFF2 / notify FFF1 など)を組み立てるCharacteristic能力の固定値です。
enum BLEUARTCapabilityFixtures {
    /// FFF0構成のService UUIDです。
    static let fff0Service = "FFF0"
    /// FFF0構成のNotify Characteristic UUIDです。
    static let fff1Notify = "FFF1"
    /// FFF0構成のWrite Characteristic UUIDです。
    static let fff2Write = "FFF2"

    /// Notify可能なFFF1です。
    static let notifyFFF1 = capability(fff1Notify, notify: true)
    /// Notifyできない(読み取りのみ相当の)FFF1です。
    static let nonNotifyFFF1 = capability(fff1Notify)
    /// 応答なし書き込みだけ可能なFFF2です。
    static let writeWithoutResponseFFF2 = capability(fff2Write, withoutResponse: true)
    /// 応答あり書き込みだけ可能なFFF2です。
    static let writeWithResponseFFF2 = capability(fff2Write, withResponse: true)
    /// 応答あり・応答なしの両方が可能なFFF2です。
    static let writeBothFFF2 = capability(fff2Write, withResponse: true, withoutResponse: true)
    /// 書き込みできないFFF2です。
    static let nonWritableFFF2 = capability(fff2Write)

    /// Characteristic能力を生成します。
    ///
    /// 責務: 省略した能力を `false` として1件の能力値を組み立てます。
    /// - Parameters:
    ///   - uuid: Characteristic UUID。
    ///   - notify: Notify可能か。
    ///   - withResponse: 応答あり書き込み可能か。
    ///   - withoutResponse: 応答なし書き込み可能か。
    /// - Returns: 能力値。
    static func capability(
        _ uuid: String,
        notify: Bool = false,
        withResponse: Bool = false,
        withoutResponse: Bool = false
    ) -> AppleBluetoothCharacteristicCapability {
        AppleBluetoothCharacteristicCapability(
            uuid: uuid,
            supportsNotify: notify,
            supportsWriteWithResponse: withResponse,
            supportsWriteWithoutResponse: withoutResponse
        )
    }
}

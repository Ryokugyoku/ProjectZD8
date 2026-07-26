#if os(iOS) || os(macOS)
import Foundation

/// Appleプラットフォームで試験する既知のBluetooth Low Energy UART構成を表します。
nonisolated struct AppleBluetoothUARTProfile: Equatable, Sendable {
    /// UART構成の由来と互換範囲です。
    enum Kind: String, Equatable, Sendable {
        /// 提供資料に基づくOBDLink MX+試験構成です。
        case obdLinkMXPlusExperimental
        /// OBDLink CX公式仕様およびSwiftOBD2が扱うFFF0構成です。
        case fff0
        /// SwiftOBD2が扱うFFE0単一Characteristic構成です。
        case ffe0
        /// SwiftOBD2がVGate iCar Pro例として扱う18F0構成です。
        case vGate18F0
    }

    /// UART構成の由来です。
    let kind: Kind
    /// UARTを公開するService UUIDです。
    let serviceUUID: String
    /// アダプターへ書き込むCharacteristic UUIDです。
    let writeCharacteristicUUID: String
    /// アダプターから通知を受けるCharacteristic UUIDです。
    let notifyCharacteristicUUID: String

    /// 既知のUUIDを正規化してUART構成を生成します。
    ///
    /// 責務: 1件の既知UART定義を大文字UUIDによる比較可能な不変値へ固定します。
    /// - Parameters:
    ///   - kind: UART構成の由来。
    ///   - serviceUUID: UARTを公開するService UUID。
    ///   - writeCharacteristicUUID: 書込Characteristic UUID。
    ///   - notifyCharacteristicUUID: 通知Characteristic UUID。
    init(
        kind: Kind,
        serviceUUID: String,
        writeCharacteristicUUID: String,
        notifyCharacteristicUUID: String
    ) {
        self.kind = kind
        self.serviceUUID = serviceUUID.uppercased()
        self.writeCharacteristicUUID = writeCharacteristicUUID.uppercased()
        self.notifyCharacteristicUUID = notifyCharacteristicUUID.uppercased()
    }

    /// 実機試験で照合する既知UART構成を優先順で返します。
    static let supported: [AppleBluetoothUARTProfile] = [
        AppleBluetoothUARTProfile(
            kind: .obdLinkMXPlusExperimental,
            serviceUUID: "B3491406-44E4-4D83-97C5-CE3190130000",
            writeCharacteristicUUID: "B3491406-44E4-4D83-97C5-CE3190130001",
            notifyCharacteristicUUID: "B3491406-44E4-4D83-97C5-CE3190130001"
        ),
        AppleBluetoothUARTProfile(
            kind: .fff0,
            serviceUUID: "FFF0",
            writeCharacteristicUUID: "FFF2",
            notifyCharacteristicUUID: "FFF1"
        ),
        AppleBluetoothUARTProfile(
            kind: .ffe0,
            serviceUUID: "FFE0",
            writeCharacteristicUUID: "FFE1",
            notifyCharacteristicUUID: "FFE1"
        ),
        AppleBluetoothUARTProfile(
            kind: .vGate18F0,
            serviceUUID: "18F0",
            writeCharacteristicUUID: "2AF1",
            notifyCharacteristicUUID: "2AF0"
        )
    ]
}

/// 1件のBLE Characteristicが公開するUART関連能力です。
nonisolated struct AppleBluetoothCharacteristicCapability: Equatable, Sendable {
    /// Characteristic UUIDです。
    let uuid: String
    /// Notifyを有効化できるかどうかです。
    let supportsNotify: Bool
    /// 応答あり書込を利用できるかどうかです。
    let supportsWriteWithResponse: Bool
    /// 応答なし書込を利用できるかどうかです。
    let supportsWriteWithoutResponse: Bool

    /// CoreBluetooth非依存のCharacteristic能力を生成します。
    ///
    /// 責務: 1件のCharacteristic識別子とUART関連プロパティを比較可能な値へ固定します。
    /// - Parameters:
    ///   - uuid: Characteristic UUID。
    ///   - supportsNotify: Notify対応状態。
    ///   - supportsWriteWithResponse: 応答あり書込対応状態。
    ///   - supportsWriteWithoutResponse: 応答なし書込対応状態。
    init(
        uuid: String,
        supportsNotify: Bool,
        supportsWriteWithResponse: Bool,
        supportsWriteWithoutResponse: Bool
    ) {
        self.uuid = uuid.uppercased()
        self.supportsNotify = supportsNotify
        self.supportsWriteWithResponse = supportsWriteWithResponse
        self.supportsWriteWithoutResponse = supportsWriteWithoutResponse
    }
}

/// 実機のService一覧から利用可能な既知UART構成を選択します。
nonisolated struct AppleBluetoothUARTProfileResolver {
    /// 実機能力を満たす最初の既知UART構成を返します。
    ///
    /// 責務: Service別Characteristic能力をNotify可能かつ書込可能な既知UART構成へ解決します。
    /// - Parameters:
    ///   - services: Service UUIDごとのCharacteristic能力。
    ///   - profiles: 優先順に照合する既知UART構成。
    /// - Returns: 必要なService、Notify、Write能力が揃う最初の構成。該当しない場合は `nil`。
    func resolve(
        services: [String: [AppleBluetoothCharacteristicCapability]],
        profiles: [AppleBluetoothUARTProfile] = AppleBluetoothUARTProfile.supported
    ) -> AppleBluetoothUARTProfile? {
        let normalizedServices = Dictionary(uniqueKeysWithValues: services.map {
            ($0.key.uppercased(), $0.value)
        })
        return profiles.first { profile in
            guard let characteristics = normalizedServices[profile.serviceUUID],
                  let notify = characteristics.first(where: {
                      $0.uuid == profile.notifyCharacteristicUUID && $0.supportsNotify
                  }),
                  let write = characteristics.first(where: {
                      $0.uuid == profile.writeCharacteristicUUID
                          && ($0.supportsWriteWithResponse || $0.supportsWriteWithoutResponse)
                  }) else {
                return false
            }
            return notify.supportsNotify
                && (write.supportsWriteWithResponse || write.supportsWriteWithoutResponse)
        }
    }
}
#endif

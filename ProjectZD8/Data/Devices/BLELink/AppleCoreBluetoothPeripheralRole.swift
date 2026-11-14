#if os(iOS) || os(macOS)
import CoreBluetooth
import Foundation

/// 1件の `CBPeripheral` を `BLEPeripheralRole` として包む薄いアダプターです。判断ロジックを持ちません。
@MainActor
final class AppleCoreBluetoothPeripheralRole: NSObject, BLEPeripheralRole, CBPeripheralDelegate {
    /// 包んでいるCoreBluetoothペリフェラルです。中央役アダプターだけが参照します。
    let peripheral: CBPeripheral

    /// ペリフェラル役イベントの通知先です。
    var eventHandler: (@MainActor (BLEPeripheralEvent) -> Void)?

    /// ペリフェラルを包み、自身をdelegateへ設定します。
    ///
    /// 責務: 1件の `CBPeripheral` のdelegate通知をこのラッパーへ集めます。
    /// - Parameter peripheral: 包むペリフェラル。
    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        peripheral.delegate = self
    }

    /// OSがペリフェラルへ割り当てた識別子です。
    var identifier: UUID { peripheral.identifier }

    /// 現在の接続状態です。
    var connectionState: BLEPeripheralConnectionState {
        switch peripheral.state {
        case .connected: .connected
        case .connecting: .connecting
        case .disconnecting: .disconnecting
        case .disconnected: .disconnected
        @unknown default: .disconnected
        }
    }

    /// 応答なし書き込みを今すぐ送信できるかどうかです。
    var canSendWriteWithoutResponse: Bool { peripheral.canSendWriteWithoutResponse }

    /// Service探索を要求します。
    ///
    /// 責務: UUID文字列を `CBUUID` へ変換してService探索を要求します。
    /// - Parameter serviceUUIDs: 探索するService UUID。`nil` は全Service。
    func discoverServices(_ serviceUUIDs: [String]?) {
        peripheral.discoverServices(serviceUUIDs?.map { CBUUID(string: $0) })
    }

    /// 1件のServiceのCharacteristic探索を要求します。
    ///
    /// 責務: UUID文字列に一致する発見済みServiceのCharacteristic探索を要求し、Serviceがなければ失敗イベントを届けます。
    /// - Parameter serviceUUID: 対象Service UUID。
    func discoverCharacteristics(forService serviceUUID: String) {
        guard let service = service(matching: serviceUUID) else {
            deliverLater(.didDiscoverCharacteristics(
                serviceUUID: serviceUUID.uppercased(),
                capabilities: [],
                errorDescription: "Service \(serviceUUID) is not discovered."
            ))
            return
        }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    /// CharacteristicのNotify状態変更を要求します。
    ///
    /// 責務: UUID文字列に一致するCharacteristicのNotify状態変更を要求し、なければ失敗イベントを届けます。
    /// - Parameters:
    ///   - enabled: 有効化する場合は `true`。
    ///   - characteristicUUID: 対象Characteristic UUID。
    ///   - serviceUUID: Characteristicを持つService UUID。
    func setNotifyValue(_ enabled: Bool, characteristicUUID: String, serviceUUID: String) {
        guard let characteristic = characteristic(matching: characteristicUUID, in: serviceUUID) else {
            deliverLater(.didUpdateNotificationState(
                characteristicUUID: characteristicUUID.uppercased(),
                isNotifying: false,
                errorDescription: "Characteristic \(characteristicUUID) is not discovered."
            ))
            return
        }
        peripheral.setNotifyValue(enabled, for: characteristic)
    }

    /// 書き込み種別ごとの最大書き込み長を返します。
    ///
    /// 責務: 書き込み種別を `CBCharacteristicWriteType` へ変換してOSの最大長を返します。
    /// - Parameter kind: 書き込み種別。
    /// - Returns: 1回で書き込める最大バイト数。
    func maximumWriteValueLength(for kind: BLEWriteKind) -> Int {
        peripheral.maximumWriteValueLength(for: Self.writeType(for: kind))
    }

    /// Characteristicへ1チャンクを書き込みます。
    ///
    /// 責務: UUID文字列に一致するCharacteristicへ書き込み、なければ応答ありの場合だけ失敗イベントを届けます。
    /// - Parameters:
    ///   - data: 書き込むバイト列。
    ///   - characteristicUUID: 対象Characteristic UUID。
    ///   - serviceUUID: Characteristicを持つService UUID。
    ///   - kind: 書き込み種別。
    func writeValue(_ data: Data, characteristicUUID: String, serviceUUID: String, kind: BLEWriteKind) {
        guard let characteristic = characteristic(matching: characteristicUUID, in: serviceUUID) else {
            if kind == .withResponse {
                deliverLater(.didWriteValue(
                    characteristicUUID: characteristicUUID.uppercased(),
                    errorDescription: "Characteristic \(characteristicUUID) is not discovered."
                ))
            }
            return
        }
        peripheral.writeValue(data, for: characteristic, type: Self.writeType(for: kind))
    }

    /// Service探索結果をイベントへ変換します。
    ///
    /// 責務: `didDiscoverServices` をService UUID一覧のイベントへ変換します。
    /// - Parameters:
    ///   - peripheral: 通知元ペリフェラル。
    ///   - error: OSのエラー。
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        let uuids = (peripheral.services ?? []).map { $0.uuid.uuidString.uppercased() }
        eventHandler?(.didDiscoverServices(serviceUUIDs: uuids, errorDescription: error?.localizedDescription))
    }

    /// Characteristic探索結果をイベントへ変換します。
    ///
    /// 責務: `didDiscoverCharacteristicsFor` をCharacteristic能力一覧のイベントへ変換します。
    /// - Parameters:
    ///   - peripheral: 通知元ペリフェラル。
    ///   - service: 探索したService。
    ///   - error: OSのエラー。
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        let capabilities = (service.characteristics ?? []).map(Self.capability(of:))
        eventHandler?(.didDiscoverCharacteristics(
            serviceUUID: service.uuid.uuidString.uppercased(),
            capabilities: capabilities,
            errorDescription: error?.localizedDescription
        ))
    }

    /// Notify状態更新をイベントへ変換します。
    ///
    /// 責務: `didUpdateNotificationStateFor` をNotify状態イベントへ変換します。
    /// - Parameters:
    ///   - peripheral: 通知元ペリフェラル。
    ///   - characteristic: 対象Characteristic。
    ///   - error: OSのエラー。
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        eventHandler?(.didUpdateNotificationState(
            characteristicUUID: characteristic.uuid.uuidString.uppercased(),
            isNotifying: characteristic.isNotifying,
            errorDescription: error?.localizedDescription
        ))
    }

    /// 値の受信をイベントへ変換します。
    ///
    /// 責務: `didUpdateValueFor` を受信値イベントへそのまま変換します。
    /// - Parameters:
    ///   - peripheral: 通知元ペリフェラル。
    ///   - characteristic: 値を持つCharacteristic。
    ///   - error: OSのエラー。
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        eventHandler?(.didReceiveValue(
            characteristicUUID: characteristic.uuid.uuidString.uppercased(),
            value: characteristic.value ?? Data(),
            errorDescription: error?.localizedDescription
        ))
    }

    /// 応答あり書き込み完了をイベントへ変換します。
    ///
    /// 責務: `didWriteValueFor` を書き込み完了イベントへ変換します。
    /// - Parameters:
    ///   - peripheral: 通知元ペリフェラル。
    ///   - characteristic: 書き込んだCharacteristic。
    ///   - error: OSのエラー。
    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        eventHandler?(.didWriteValue(
            characteristicUUID: characteristic.uuid.uuidString.uppercased(),
            errorDescription: error?.localizedDescription
        ))
    }

    /// 応答なし書き込みの送信可能通知をイベントへ変換します。
    ///
    /// 責務: `peripheralIsReady(toSendWriteWithoutResponse:)` を送信可能イベントへ変換します。
    /// - Parameter peripheral: 通知元ペリフェラル。
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        eventHandler?(.isReadyToSendWriteWithoutResponse)
    }

    /// UUID文字列に一致する発見済みServiceを返します。
    ///
    /// 責務: UUID文字列を発見済み `CBService` へ解決します。
    /// - Parameter uuid: Service UUID。
    /// - Returns: 一致するService。なければ `nil`。
    private func service(matching uuid: String) -> CBService? {
        peripheral.services?.first { $0.uuid.uuidString.caseInsensitiveCompare(uuid) == .orderedSame }
    }

    /// UUID文字列に一致する発見済みCharacteristicを返します。
    ///
    /// 責務: Service・Characteristic UUID文字列を発見済み `CBCharacteristic` へ解決します。
    /// - Parameters:
    ///   - uuid: Characteristic UUID。
    ///   - serviceUUID: Service UUID。
    /// - Returns: 一致するCharacteristic。なければ `nil`。
    private func characteristic(matching uuid: String, in serviceUUID: String) -> CBCharacteristic? {
        service(matching: serviceUUID)?.characteristics?.first {
            $0.uuid.uuidString.caseInsensitiveCompare(uuid) == .orderedSame
        }
    }

    /// 呼び出し元の処理が終わった後にイベントを届けます。
    ///
    /// 責務: 要求メソッドの中で同期的に再入しないよう、失敗イベントを次のメインアクター実行機会へ遅らせます。
    /// - Parameter event: 届けるイベント。
    private func deliverLater(_ event: BLEPeripheralEvent) {
        Task { @MainActor [weak self] in
            self?.eventHandler?(event)
        }
    }

    /// 書き込み種別を `CBCharacteristicWriteType` へ変換します。
    ///
    /// 責務: 自前の書き込み種別をCoreBluetoothの値へ写します。
    /// - Parameter kind: 書き込み種別。
    /// - Returns: 対応するCoreBluetoothの書き込み種別。
    private static func writeType(for kind: BLEWriteKind) -> CBCharacteristicWriteType {
        switch kind {
        case .withResponse: .withResponse
        case .withoutResponse: .withoutResponse
        }
    }

    /// `CBCharacteristic` をUART関連能力へ変換します。
    ///
    /// 責務: Characteristicのプロパティを既存のUART能力値へ写します。
    /// - Parameter characteristic: 変換対象。
    /// - Returns: UART関連能力。
    private static func capability(of characteristic: CBCharacteristic) -> AppleBluetoothCharacteristicCapability {
        AppleBluetoothCharacteristicCapability(
            uuid: characteristic.uuid.uuidString,
            supportsNotify: characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate),
            supportsWriteWithResponse: characteristic.properties.contains(.write),
            supportsWriteWithoutResponse: characteristic.properties.contains(.writeWithoutResponse)
        )
    }
}
#endif

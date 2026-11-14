import Foundation
@testable import ProjectZD8

/// 実物の `BLEAdapterLink` をフェイクの中央役・ペリフェラル役・待機手段と組み合わせ、状態と受信を記録する準備です。
@MainActor
final class BLEAdapterLinkTestHarness {
    /// 登録済みアダプターの識別子です。
    nonisolated static let targetIdentifier = UUID(uuidString: "6F1D2C3B-4A59-4E68-8D7C-0123456789AB")!
    /// 登録済みでない別機器の識別子です。
    nonisolated static let otherIdentifier = UUID(uuidString: "0A1B2C3D-4E5F-4061-8273-9485A6B7C8D9")!
    /// 探索各段階の待機上限としてテストが注入する時間です。
    nonisolated static let discoveryStepTimeout: Duration = .seconds(7)

    /// 中央役のフェイクです。
    let central: BLECentralRoleFake
    /// 登録済みアダプター役のフェイクです。
    let peripheral: BLEPeripheralRoleFake
    /// 待機手段です。
    let sleepController = BLEManualSleepController()
    /// テスト対象のリンクです。
    let link: BLEAdapterLink
    /// 状態変化ハンドラへ届いた状態を届いた順に保持します。
    private(set) var states: [AdapterLinkState] = []
    /// 受信ハンドラへ届いたバイト列を届いた順に保持します。
    private(set) var received: [Data] = []

    /// フェイクとリンクを組み立てます。
    ///
    /// 責務: 指定の電源状態・再試行上限でリンクを生成し、状態と受信の記録を結び付けます。
    /// - Parameters:
    ///   - powerState: 中央役の初期電源状態。
    ///   - maximumConsecutiveReconnects: 注入する再試行上限。
    ///   - peripheralState: 登録済みアダプター役の初期接続状態。
    init(
        powerState: BLECentralPowerState = .poweredOn,
        maximumConsecutiveReconnects: Int = 3,
        peripheralState: BLEPeripheralConnectionState = .disconnected
    ) {
        central = BLECentralRoleFake(powerState: powerState)
        peripheral = BLEPeripheralRoleFake(identifier: Self.targetIdentifier, connectionState: peripheralState)
        link = BLEAdapterLink(
            central: central,
            limits: BLEAdapterLinkLimits(
                maximumConsecutiveReconnects: maximumConsecutiveReconnects,
                discoveryStepTimeout: Self.discoveryStepTimeout
            ),
            sleep: sleepController.sleep
        )
        link.stateDidChange = { [weak self] in self?.states.append($0) }
        link.dataDidReceive = { [weak self] in self?.received.append($0) }
    }

    /// 指定識別子の登録済みアダプター設定を生成します。
    ///
    /// 責務: BLEアダプターのデフォルト設定を1件組み立てます。
    /// - Parameter systemIdentifier: 登録済みのシステム識別子。
    /// - Returns: デフォルト設定。
    static func preference(systemIdentifier: String = targetIdentifier.uuidString) -> DefaultAdapterPreference {
        DefaultAdapterPreference(
            adapterID: "ble-test-adapter",
            transportMode: .bluetooth,
            displayName: "Test Adapter",
            systemIdentifier: systemIdentifier
        )
    }

    /// 登録済みアダプターでリンクを開始します。
    ///
    /// 責務: 指定識別子の設定で `start(preference:)` を呼びます。
    /// - Parameter systemIdentifier: 登録済みのシステム識別子。
    func start(systemIdentifier: String = targetIdentifier.uuidString) {
        link.start(preference: Self.preference(systemIdentifier: systemIdentifier))
    }

    /// 取得で登録済みアダプターが見つかる状態でリンクを開始します。
    ///
    /// 責務: 取得結果に登録済みアダプター役を設定して開始し、接続要求まで進めます。
    func startConnectingViaRetrieve() {
        central.retrieveResult = [peripheral]
        start()
    }

    /// 接続成功イベントを流します。
    ///
    /// 責務: 登録済みアダプター役の接続成功を中央役から通知します。
    func emitConnected() {
        peripheral.connectionState = .connected
        central.emit(.didConnect(peripheral))
    }

    /// FFF0構成のService・Characteristic探索結果を流します。
    ///
    /// 責務: FFF0 Serviceの発見と、そのCharacteristic能力の発見を順に通知します。
    /// - Parameters:
    ///   - notify: FFF1の能力。
    ///   - write: FFF2の能力。
    func emitFFF0Discovery(
        notify: AppleBluetoothCharacteristicCapability = BLEUARTCapabilityFixtures.notifyFFF1,
        write: AppleBluetoothCharacteristicCapability = BLEUARTCapabilityFixtures.writeWithoutResponseFFF2
    ) {
        peripheral.emit(.didDiscoverServices(serviceUUIDs: [BLEUARTCapabilityFixtures.fff0Service], errorDescription: nil))
        peripheral.emit(.didDiscoverCharacteristics(
            serviceUUID: BLEUARTCapabilityFixtures.fff0Service,
            capabilities: [notify, write],
            errorDescription: nil
        ))
    }

    /// FFF1のNotify有効化完了を流します。
    ///
    /// 責務: Notify Characteristicの有効化完了を通知します。
    func emitNotifyEnabled() {
        peripheral.emit(.didUpdateNotificationState(
            characteristicUUID: BLEUARTCapabilityFixtures.fff1Notify,
            isNotifying: true,
            errorDescription: nil
        ))
    }

    /// 取得経由で `ready` まで進めます。
    ///
    /// 責務: 開始・接続成功・FFF0探索・Notify有効化を順に流します。
    /// - Parameter write: FFF2の能力。
    func driveToReady(write: AppleBluetoothCharacteristicCapability = BLEUARTCapabilityFixtures.writeWithoutResponseFFF2) {
        startConnectingViaRetrieve()
        emitConnected()
        emitFFF0Discovery(write: write)
        emitNotifyEnabled()
    }

    /// 書き込みを別タスクで開始します。
    ///
    /// 責務: リンクへの1件の書き込みを結果記録付きで開始します。
    /// - Parameter data: 書き込むバイト列。
    /// - Returns: 結果を記録する書き込み。
    func beginWrite(_ data: Data) -> BLEWriteAttemptRecorder {
        let link = link
        return BLEWriteAttemptRecorder { try await link.write(data) }
    }

    /// テスト後に待機と書き込みを取り残さないよう後始末します。
    ///
    /// 責務: リンクを停止して書き込み待ちを終わらせ、残った待機を全て戻します。
    func tearDown() {
        link.stop()
        sleepController.drain()
    }
}

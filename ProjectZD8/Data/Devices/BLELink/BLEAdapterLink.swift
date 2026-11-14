#if os(iOS) || os(macOS)
import Foundation
import OSLog

/// 登録済みアダプターへ保留中の接続要求を出し続け、状態復元に対応する常駐BLEリンクです。
///
/// CoreBluetoothには直接触れず、注入された `BLECentralRole` と、そこから得た `BLEPeripheralRole` だけを使います。
/// 全メソッドとイベント処理はメインアクターで動きます。
@MainActor
final class BLEAdapterLink: AdapterLinkPort {
    /// 状態として公開しない内部の進行段階です。
    private enum Phase: Equatable {
        /// `start` されていません。
        case inactive
        /// Bluetoothが `poweredOn` になるのを待っています。
        case waitingForPower
        /// 登録済みアダプターの広告をスキャンしています。
        case scanning
        /// 接続要求の結果を待っています。
        case connecting
        /// Service探索の結果を待っています。
        case discoveringServices
        /// Service別Characteristic探索の結果を待っています。
        case discoveringCharacteristics
        /// Notify有効化の結果を待っています。
        case enablingNotify
        /// 再試行のために出した接続キャンセルの完了(切断通知)を待っています。
        case cancellingForRetry
        /// 送受信できます。
        case ready
        /// 終端の失敗で止まっています。`stop()`→`start(preference:)` でやり直します。
        case terminal
    }

    /// リンク状態が変化したときに新しい状態を受け取る処理です。
    var stateDidChange: (@MainActor (AdapterLinkState) -> Void)?
    /// アダプターから受信したバイトを届いた順にそのまま受け取る処理です。
    var dataDidReceive: (@MainActor (Data) -> Void)?
    /// 現在のリンク状態です。
    private(set) var state: AdapterLinkState = .idle

    /// 注入されたBluetooth中央役です。
    private let central: any BLECentralRole
    /// 再試行と探索待機の上限値です。
    private let limits: BLEAdapterLinkLimits
    /// スキャンと探索で指定する既知UART Service UUIDです。
    private let serviceUUIDs = AppleBluetoothUARTProfile.supported.map(\.serviceUUID)
    /// 全状態遷移を記録するロガーです。
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProjectZD8", category: "BLELink")
    /// 探索各段階とキャンセル完了待ちの期限です。
    private let deadline: BLEAdapterLinkDeadline
    /// 呼び出し順の書き込みキューです。
    private let writeQueue = BLEAdapterLinkWriteQueue()
    /// 連続失敗の計数です。
    private var retryCounter: BLEAdapterLinkRetryCounter
    /// 探索結果の集約です。
    private var aggregator = BLEUARTDiscoveryAggregator()
    /// 内部の進行段階です。
    private var phase: Phase = .inactive
    /// 登録済みアダプターの識別子です。`start` で判明します。
    private var targetIdentifier: UUID?
    /// 現在扱っているペリフェラルです。接続保留中も保持します。
    private var peripheral: (any BLEPeripheralRole)?
    /// 状態復元で渡され、まだ引き継いでいないペリフェラルです。`start` より先に届いた分もここで保持します。
    private var restoredPeripherals: [any BLEPeripheralRole] = []
    /// 解決済みの送受信路です。
    private var channel: BLEResolvedUARTChannel?

    /// 中央役・上限値・待機手段を注入して生成します。
    ///
    /// 責務: 依存を固定し、`start` より前に届く状態復元イベントも受け取れるよう中央役の通知先を設定します。
    /// - Parameters:
    ///   - central: Bluetooth中央役。
    ///   - limits: 再試行と探索待機の上限値。
    ///   - sleep: 期限待ちに使う待機処理。テストは実時間を待たない実装を渡します。
    init(
        central: any BLECentralRole,
        limits: BLEAdapterLinkLimits = .standard,
        sleep: @escaping BLEAdapterLinkDeadline.Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.central = central
        self.limits = limits
        deadline = BLEAdapterLinkDeadline(sleep: sleep)
        retryCounter = BLEAdapterLinkRetryCounter(maximumConsecutiveReconnects: limits.maximumConsecutiveReconnects)
        central.eventHandler = { [weak self] event in
            self?.handleCentralEvent(event)
        }
    }

    /// 登録済みアダプターへのリンクを開始します。
    ///
    /// 責務: 進行中のリンクを破棄し、識別子を検証して、Bluetooth状態に応じた接続手順を始めます。
    /// - Parameter preference: 接続対象の登録済みアダプター設定。
    func start(preference: DefaultAdapterPreference) {
        tearDownActivity(writeError: .stopped)
        retryCounter.reset()
        guard let identifier = UUID(uuidString: preference.systemIdentifier) else {
            targetIdentifier = nil
            phase = .terminal
            transition(to: .disconnected(.invalidIdentifier))
            return
        }
        targetIdentifier = identifier
        phase = .waitingForPower
        logger.info("BLELink start target=\(identifier.uuidString, privacy: .public)")
        applyPowerState(central.powerState)
    }

    /// リンクを停止して `idle` へ戻します。
    ///
    /// 責務: スキャン・接続・期限・書き込み待ちを破棄して未開始状態へ戻します。
    func stop() {
        tearDownActivity(writeError: .stopped)
        targetIdentifier = nil
        phase = .inactive
        transition(to: .idle)
    }

    /// アダプターへバイト列を送信します。
    ///
    /// 責務: `ready` の時だけ書き込みキューへ渡し、呼び出し順に送り終えるまで待ちます。
    /// - Parameter data: 送信するバイト列。
    /// - Throws: `ready` でない場合は `AdapterLinkWriteError.notReady`。完了前の切断・停止・OS失敗はそれぞれのエラー。
    func write(_ data: Data) async throws {
        guard phase == .ready else { throw AdapterLinkWriteError.notReady }
        try await writeQueue.enqueue(data)
    }

    // MARK: - Central events

    /// 中央役イベントを処理します。
    ///
    /// 責務: 1件の中央役イベントを現在の段階に応じた処理へ振り分け、現在のペリフェラル以外のイベントを捨てます。
    /// - Parameter event: 中央役イベント。
    private func handleCentralEvent(_ event: BLECentralEvent) {
        switch event {
        case .powerStateDidUpdate(let powerState):
            logger.info("BLELink power=\(String(describing: powerState), privacy: .public)")
            applyPowerState(powerState)
        case .willRestore(let restored):
            handleRestoration(restored)
        case .didDiscover(let discovered):
            handleDiscovery(discovered)
        case .didConnect(let connected):
            guard isCurrent(connected), phase == .connecting else { return }
            startDiscovery()
        case .didFailToConnect(let failed, let errorDescription):
            guard isCurrent(failed), phase == .connecting else { return }
            handleLinkFailure(.connectionFailed(errorDescription: errorDescription))
        case .didDisconnect(let disconnected, let errorDescription):
            guard isCurrent(disconnected) else { return }
            handleDisconnection(errorDescription: errorDescription)
        }
    }

    /// Bluetooth状態を接続手順へ反映します。
    ///
    /// 責務: `poweredOn` で接続手順を始め、利用不可・未確定では進行中の手順を破棄して対応する状態を出します。
    /// - Parameter powerState: 現在のBluetooth状態。
    private func applyPowerState(_ powerState: BLECentralPowerState) {
        guard targetIdentifier != nil, phase != .inactive, phase != .terminal else { return }
        switch powerState {
        case .poweredOn:
            if phase == .waitingForPower {
                beginConnectionProcedure()
            }
        case .poweredOff:
            interruptForUnavailablePower(next: .disconnected(.bluetoothPoweredOff))
        case .unauthorized:
            interruptForUnavailablePower(next: .disconnected(.bluetoothUnauthorized))
        case .unsupported:
            interruptForUnavailablePower(next: .disconnected(.bluetoothUnsupported))
        case .unknown, .resetting:
            interruptForUnavailablePower(next: .idle)
        }
    }

    /// 状態復元されたペリフェラルを記録し、引き継げるなら接続手順へ入ります。
    ///
    /// 責務: 復元一覧を保持し、識別子が判明済みかつ `poweredOn` で一致する機器がある時だけ引き継ぎます。
    /// - Parameter restored: OSが復元したペリフェラル一覧。
    private func handleRestoration(_ restored: [any BLEPeripheralRole]) {
        restoredPeripherals = restored
        logger.info("BLELink restored peripherals count=\(restored.count, privacy: .public)")
        guard let targetIdentifier,
              restored.contains(where: { $0.identifier == targetIdentifier }),
              central.powerState == .poweredOn,
              phase == .waitingForPower || phase == .scanning else {
            return
        }
        if phase == .scanning {
            central.stopScan()
        }
        beginConnectionProcedure()
    }

    /// スキャンで発見した機器が登録済みなら接続します。
    ///
    /// 責務: 識別子が一致する発見だけでスキャンを止めて接続要求を出し、他の機器は無視してスキャンを続けます。
    /// - Parameter discovered: 発見したペリフェラル。
    private func handleDiscovery(_ discovered: any BLEPeripheralRole) {
        guard phase == .scanning, discovered.identifier == targetIdentifier else { return }
        central.stopScan()
        requestConnection(to: discovered)
    }

    /// 現在のペリフェラルの切断通知を段階に応じて処理します。
    ///
    /// 責務: 再試行のためのキャンセル完了なら再接続し、接続中・探索中・送受信中なら切断失敗として扱います。
    /// - Parameter errorDescription: OSのエラー説明。
    private func handleDisconnection(errorDescription: String?) {
        switch phase {
        case .cancellingForRetry:
            reconnectAfterCancellation()
        case .connecting, .discoveringServices, .discoveringCharacteristics, .enablingNotify, .ready:
            handleLinkFailure(.peripheralDisconnected(errorDescription: errorDescription))
        case .inactive, .waitingForPower, .scanning, .terminal:
            return
        }
    }

    // MARK: - Connection procedure

    /// 復元・取得・スキャンの順で登録済みアダプターを探し、接続手順を始めます。
    ///
    /// 責務: 一致する復元済み機器を優先し、次に識別子取得、どちらもなければ既知UART Service限定スキャンへ進みます。
    private func beginConnectionProcedure() {
        guard let targetIdentifier else { return }
        if let restored = takeRestoredPeripheral(matching: targetIdentifier) {
            adoptRestoredPeripheral(restored)
            return
        }
        let retrieved = central.retrievePeripherals(withIdentifiers: [targetIdentifier])
        if let known = retrieved.first(where: { $0.identifier == targetIdentifier }) {
            requestConnection(to: known)
            return
        }
        phase = .scanning
        transition(to: .awaitingPeripheral)
        central.scanForPeripherals(withServices: serviceUUIDs)
    }

    /// 復元一覧から登録済み識別子に一致する機器を取り出します。
    ///
    /// 責務: 一致する機器があれば返して復元一覧を空にし、なければ一覧を残します。
    /// - Parameter identifier: 登録済み識別子。
    /// - Returns: 一致した復元済みペリフェラル。なければ `nil`。
    private func takeRestoredPeripheral(matching identifier: UUID) -> (any BLEPeripheralRole)? {
        guard let matched = restoredPeripherals.first(where: { $0.identifier == identifier }) else { return nil }
        restoredPeripherals.removeAll()
        return matched
    }

    /// 復元済み機器を接続状態に応じて引き継ぎます。
    ///
    /// 責務: 接続済みなら探索へ、未接続なら接続要求へ進めます。
    /// - Parameter restored: 一致した復元済みペリフェラル。
    private func adoptRestoredPeripheral(_ restored: any BLEPeripheralRole) {
        logger.info("BLELink adopting restored peripheral state=\(String(describing: restored.connectionState), privacy: .public)")
        if restored.connectionState == .connected {
            attach(restored)
            startDiscovery()
        } else {
            requestConnection(to: restored)
        }
    }

    /// ペリフェラルへタイムアウトなしの接続要求を出します。
    ///
    /// 責務: 対象を現在のペリフェラルとして保持し、`connecting` を出してから接続要求を出します。
    /// - Parameter target: 接続対象。
    private func requestConnection(to target: any BLEPeripheralRole) {
        attach(target)
        phase = .connecting
        transition(to: .connecting)
        central.connect(target)
    }

    /// ペリフェラルを現在の対象として保持し、イベントを受け取ります。
    ///
    /// 責務: 以前の対象の通知先を外し、新しい対象の通知先をこのリンクへ結び付けます。
    /// - Parameter target: 新しい対象。
    private func attach(_ target: any BLEPeripheralRole) {
        if let peripheral, peripheral !== target {
            peripheral.eventHandler = nil
        }
        peripheral = target
        target.eventHandler = { [weak self, weak target] event in
            guard let self, let target else { return }
            self.handlePeripheralEvent(event, from: target)
        }
    }

    /// 現在のペリフェラルかどうかを返します。
    ///
    /// 責務: イベント送信元を現在の対象と同一インスタンスで照合します。
    /// - Parameter candidate: 照合するペリフェラル。
    /// - Returns: 現在の対象なら `true`。
    private func isCurrent(_ candidate: any BLEPeripheralRole) -> Bool {
        guard let peripheral else { return false }
        return peripheral === candidate
    }

    // MARK: - Discovery

    /// 接続済みペリフェラルの探索を始めます。
    ///
    /// 責務: 集約を初期化して `discovering` を出し、期限を設定してService探索を要求します。
    private func startDiscovery() {
        guard let peripheral else { return }
        aggregator = BLEUARTDiscoveryAggregator()
        channel = nil
        phase = .discoveringServices
        transition(to: .discovering)
        armDeadline()
        peripheral.discoverServices(serviceUUIDs)
    }

    /// ペリフェラル役イベントを処理します。
    ///
    /// 責務: 現在の対象からのイベントだけを段階に応じた探索・受信・書き込み処理へ振り分けます。
    /// - Parameters:
    ///   - event: ペリフェラル役イベント。
    ///   - source: イベント送信元。
    private func handlePeripheralEvent(_ event: BLEPeripheralEvent, from source: any BLEPeripheralRole) {
        guard isCurrent(source) else { return }
        switch event {
        case .didDiscoverServices(let serviceUUIDs, let errorDescription):
            guard phase == .discoveringServices else { return }
            handleServicesDiscovered(serviceUUIDs, errorDescription: errorDescription, on: source)
        case .didDiscoverCharacteristics(let serviceUUID, let capabilities, let errorDescription):
            guard phase == .discoveringCharacteristics else { return }
            handleCharacteristicsDiscovered(serviceUUID, capabilities: capabilities, errorDescription: errorDescription, on: source)
        case .didUpdateNotificationState(let characteristicUUID, let isNotifying, let errorDescription):
            guard phase == .enablingNotify, characteristicUUID.uppercased() == channel?.notifyCharacteristicUUID else { return }
            handleNotificationState(isNotifying: isNotifying, errorDescription: errorDescription)
        case .didReceiveValue(let characteristicUUID, let value, let errorDescription):
            guard phase == .ready, characteristicUUID.uppercased() == channel?.notifyCharacteristicUUID else { return }
            if let errorDescription {
                logger.error("BLELink receive error=\(errorDescription, privacy: .public)")
                return
            }
            dataDidReceive?(value)
        case .didWriteValue(_, let errorDescription):
            writeQueue.handleWriteCompleted(errorDescription: errorDescription)
        case .isReadyToSendWriteWithoutResponse:
            writeQueue.handleReadyToSend()
        }
    }

    /// Service探索結果を処理します。
    ///
    /// 責務: 失敗なら探索失敗とし、成功ならService別Characteristic探索を要求します(Serviceがなければ直ちに解決します)。
    /// - Parameters:
    ///   - discovered: 発見したService UUID。
    ///   - errorDescription: OSのエラー説明。
    ///   - source: 探索したペリフェラル。
    private func handleServicesDiscovered(_ discovered: [String], errorDescription: String?, on source: any BLEPeripheralRole) {
        if let errorDescription {
            failDiscovery(.discoveryFailed(errorDescription: errorDescription))
            return
        }
        let pending = aggregator.beginServices(discovered)
        guard !pending.isEmpty else {
            resolveDiscoveredChannel(on: source)
            return
        }
        phase = .discoveringCharacteristics
        armDeadline()
        for serviceUUID in pending {
            guard phase == .discoveringCharacteristics, isCurrent(source) else { return }
            source.discoverCharacteristics(forService: serviceUUID)
        }
    }

    /// 1件のServiceのCharacteristic探索結果を処理します。
    ///
    /// 責務: 失敗なら探索失敗とし、成功なら集約へ記録して全Service分そろった時点で解決します。
    /// - Parameters:
    ///   - serviceUUID: 探索したService UUID。
    ///   - capabilities: 発見したCharacteristic能力。
    ///   - errorDescription: OSのエラー説明。
    ///   - source: 探索したペリフェラル。
    private func handleCharacteristicsDiscovered(
        _ serviceUUID: String,
        capabilities: [AppleBluetoothCharacteristicCapability],
        errorDescription: String?,
        on source: any BLEPeripheralRole
    ) {
        if let errorDescription {
            failDiscovery(.discoveryFailed(errorDescription: errorDescription))
            return
        }
        guard aggregator.recordCharacteristics(serviceUUID: serviceUUID, capabilities: capabilities) else { return }
        if aggregator.isComplete {
            resolveDiscoveredChannel(on: source)
        } else {
            armDeadline()
        }
    }

    /// 集めた能力から送受信路を解決し、Notifyを有効化します。
    ///
    /// 責務: 既知UART構成に一致すればNotify有効化を要求し、一致しなければ終端の失敗とします。
    /// - Parameter source: 探索したペリフェラル。
    private func resolveDiscoveredChannel(on source: any BLEPeripheralRole) {
        guard let resolved = aggregator.resolveChannel() else {
            failTerminally(.unknownUARTProfile)
            return
        }
        logger.info("BLELink resolved service=\(resolved.serviceUUID, privacy: .public) write=\(String(describing: resolved.writeKind), privacy: .public)")
        channel = resolved
        phase = .enablingNotify
        armDeadline()
        source.setNotifyValue(true, characteristicUUID: resolved.notifyCharacteristicUUID, serviceUUID: resolved.serviceUUID)
    }

    /// Notify状態更新を処理します。
    ///
    /// 責務: 有効化の完了を確認できた時だけ `ready` にし、失敗・無効のままなら探索失敗とします。
    /// - Parameters:
    ///   - isNotifying: 更新後のNotify状態。
    ///   - errorDescription: OSのエラー説明。
    private func handleNotificationState(isNotifying: Bool, errorDescription: String?) {
        if let errorDescription {
            failDiscovery(.discoveryFailed(errorDescription: errorDescription))
        } else if isNotifying {
            becomeReady()
        } else {
            failDiscovery(.discoveryFailed(errorDescription: "Notify was not enabled."))
        }
    }

    /// 送受信できる状態へ進みます。
    ///
    /// 責務: 期限を止めて連続失敗数を戻し、書き込み先を設定して `ready` を出します。
    private func becomeReady() {
        guard let peripheral, let channel else { return }
        deadline.cancel()
        retryCounter.reset()
        phase = .ready
        writeQueue.activate(BLEAdapterLinkWriteQueue.Target(
            peripheral: peripheral,
            serviceUUID: channel.serviceUUID,
            characteristicUUID: channel.writeCharacteristicUUID,
            kind: channel.writeKind
        ))
        transition(to: .ready)
    }

    // MARK: - Failure and retry

    /// 探索段階の期限を設定し直します。
    ///
    /// 責務: 段階が進むたびに既存の期限を捨て、新しい段階の待機上限を設定します。
    private func armDeadline() {
        deadline.arm(after: limits.discoveryStepTimeout) { [weak self] in
            self?.handleDeadlineExpired()
        }
    }

    /// 期限切れを段階に応じて処理します。
    ///
    /// 責務: 探索中なら探索の待機上限超過とし、キャンセル完了待ちなら切断通知を待たずに再接続します。
    private func handleDeadlineExpired() {
        switch phase {
        case .discoveringServices, .discoveringCharacteristics, .enablingNotify:
            failDiscovery(.discoveryTimedOut)
        case .cancellingForRetry:
            logger.error("BLELink cancellation did not complete in time; reconnecting")
            reconnectAfterCancellation()
        case .inactive, .waitingForPower, .scanning, .connecting, .ready, .terminal:
            return
        }
    }

    /// 接続済みのまま探索が失敗したときに再試行へ進めます。
    ///
    /// 責務: 理由を出して失敗を数え、上限内なら接続をキャンセルして切断通知を待ち、超えたら終端にします。
    /// - Parameter reason: 探索失敗の理由。
    private func failDiscovery(_ reason: AdapterLinkDisconnectReason) {
        discardLinkResources()
        transition(to: .disconnected(reason))
        guard retryCounter.recordFailure() else {
            failTerminally(.retryLimitExceeded)
            return
        }
        guard let peripheral else { return }
        phase = .cancellingForRetry
        armDeadline()
        central.cancelConnection(peripheral)
    }

    /// 接続失敗・切断後に再接続へ進めます。
    ///
    /// 責務: 理由を出して失敗を数え、上限内なら同じペリフェラルへ接続要求を出し直し、超えたら終端にします。
    /// - Parameter reason: 切断・接続失敗の理由。
    private func handleLinkFailure(_ reason: AdapterLinkDisconnectReason) {
        discardLinkResources()
        transition(to: .disconnected(reason))
        guard retryCounter.recordFailure() else {
            failTerminally(.retryLimitExceeded)
            return
        }
        guard let peripheral else { return }
        requestConnection(to: peripheral)
    }

    /// 再試行のためのキャンセルが終わった後に再接続します。
    ///
    /// 責務: キャンセル完了待ちの期限を止め、同じペリフェラルへ接続要求を出し直します。
    private func reconnectAfterCancellation() {
        deadline.cancel()
        guard let peripheral else { return }
        requestConnection(to: peripheral)
    }

    /// 終端の失敗で接続要求を止めます。
    ///
    /// 責務: スキャン・接続・期限・書き込み待ちを破棄し、終端の理由を出します。
    /// - Parameter reason: 終端の理由。
    private func failTerminally(_ reason: AdapterLinkDisconnectReason) {
        tearDownActivity(writeError: .linkLost)
        phase = .terminal
        transition(to: .disconnected(reason))
    }

    /// Bluetoothが使えなくなったときに進行中の手順を破棄します。
    ///
    /// 責務: OSが接続を無効にした前提でCoreBluetoothを呼ばずに対象を手放し、電源回復待ちへ戻します。
    /// - Parameter next: 出す状態。
    private func interruptForUnavailablePower(next: AdapterLinkState) {
        discardLinkResources()
        detachPeripheral()
        phase = .waitingForPower
        transition(to: next)
    }

    /// 期限・書き込み先・送受信路を破棄します。
    ///
    /// 責務: 送受信路に属する一時資源を捨て、待機中の書き込みを `linkLost` で終えます。
    private func discardLinkResources() {
        deadline.cancel()
        writeQueue.failAll(with: .linkLost)
        channel = nil
    }

    /// 進行中のスキャン・接続・期限・書き込み待ちを全て破棄します。
    ///
    /// 責務: Bluetoothが使える時だけスキャン停止と接続キャンセルを呼び、対象と一時資源を手放します。
    /// - Parameter writeError: 待機中の書き込みへ返すエラー。
    private func tearDownActivity(writeError: AdapterLinkWriteError) {
        deadline.cancel()
        writeQueue.failAll(with: writeError)
        channel = nil
        let isPoweredOn = central.powerState == .poweredOn
        if phase == .scanning, isPoweredOn {
            central.stopScan()
        }
        if let peripheral, isPoweredOn {
            central.cancelConnection(peripheral)
        }
        detachPeripheral()
    }

    /// 現在のペリフェラルを手放します。
    ///
    /// 責務: 通知先を外して参照を破棄します。
    private func detachPeripheral() {
        peripheral?.eventHandler = nil
        peripheral = nil
    }

    /// 状態を更新して通知します。
    ///
    /// 責務: 変化した時だけ状態を置き換え、遷移をログへ出して通知先へ渡します。
    /// - Parameter newState: 新しい状態。
    private func transition(to newState: AdapterLinkState) {
        guard newState != state else { return }
        let oldState = state
        state = newState
        logger.info("BLELink \(String(describing: oldState), privacy: .public) -> \(String(describing: newState), privacy: .public)")
        stateDidChange?(newState)
    }
}
#endif

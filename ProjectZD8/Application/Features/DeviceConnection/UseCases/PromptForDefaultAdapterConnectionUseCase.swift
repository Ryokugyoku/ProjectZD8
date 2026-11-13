/// 保存済みBLEアダプターの到来をユーザー承認付き接続要求へ変換します。
@MainActor
final class PromptForDefaultAdapterConnectionUseCase {
    /// 保存済み既定アダプターを読み込むユースケースです。
    private let defaultAdapterPreference: DefaultAdapterPreferenceUseCase

    /// BLEアダプターの到来を監視する境界です。
    private let arrivalMonitor: any DefaultAdapterArrivalMonitoring

    /// ユーザーへ接続確認を提示する境界です。
    private let connectionPrompt: any DefaultAdapterConnectionPrompting

    /// 承認済み終端を接続ワークフローへ渡す処理です。
    private let connectionRequested: @MainActor (OBDConnectionEndpoint) -> Void

    /// 通知準備の世代を識別する値です。
    private var preparationGeneration = 0

    /// 既定設定、到来監視、確認通知を注入して生成します。
    ///
    /// 責務: 既定BLE到来からユーザー承認済み接続要求までの依存関係を固定します。
    /// - Parameters:
    ///   - defaultAdapterPreference: 保存済み既定アダプターの読込元。
    ///   - arrivalMonitor: BLE到来監視境界。
    ///   - connectionPrompt: 接続確認通知境界。
    ///   - connectionRequested: ユーザーが接続を了承した終端の通知先。
    init(
        defaultAdapterPreference: DefaultAdapterPreferenceUseCase,
        arrivalMonitor: any DefaultAdapterArrivalMonitoring,
        connectionPrompt: any DefaultAdapterConnectionPrompting,
        connectionRequested: @escaping @MainActor (OBDConnectionEndpoint) -> Void
    ) {
        self.defaultAdapterPreference = defaultAdapterPreference
        self.arrivalMonitor = arrivalMonitor
        self.connectionPrompt = connectionPrompt
        self.connectionRequested = connectionRequested
    }

    /// 保存済みBLEアダプターへの到来監視と接続確認通知を有効化します。
    ///
    /// 責務: 現在の既定BLE設定を通知許可済みの到来監視へ反映します。
    func start() {
        preparationGeneration &+= 1
        let generation = preparationGeneration
        arrivalMonitor.stopMonitoring()

        guard let preference = defaultAdapterPreference.load(),
              preference.connectionTransport == .bluetoothLowEnergy else {
            return
        }

        Task { [weak self] in
            guard let self,
                  await connectionPrompt.prepare(acceptance: connectionRequested),
                  generation == preparationGeneration else {
                return
            }
            arrivalMonitor.startMonitoring(preference: preference) { [weak self] endpoint in
                self?.connectionPrompt.present(endpoint: endpoint)
            }
        }
    }

    /// 既定BLEアダプターの到来監視を無効化します。
    ///
    /// 責務: 通知準備世代を無効化して現在の到来監視を停止します。
    func stop() {
        preparationGeneration &+= 1
        arrivalMonitor.stopMonitoring()
    }
}

import Observation

/// アダプターの探索と既定アダプターを管理します。
@MainActor
@Observable
final class DeviceConnectionModel {
    /// 画面が描画する状態です。
    private(set) var state = DeviceConnectionState()

    @ObservationIgnored private let discovery: any AdapterDiscoveryPort
    @ObservationIgnored private let defaultStore: any DefaultAdapterStorePort
    @ObservationIgnored private let isDemoModeEnabled: @MainActor () -> Bool
    @ObservationIgnored private let demoAdapter: AdapterDescriptor
    @ObservationIgnored private let connectRequested: @MainActor (AdapterDescriptor) -> Void
    @ObservationIgnored private var generation = 0

    /// 責務: 探索・保存・デモ設定の依存を受け取り、保存済みの既定アダプターを読み込みます。
    /// - Parameters:
    ///   - isDemoModeEnabled: 探索完了時点でデモモードが有効かを返します。
    ///   - demoAdapter: デモモード中に結果へ加える模擬アダプター。
    ///   - connectRequested: アダプターの出現通知をユーザーが受け入れた時の接続要求の転送先。
    init(
        discovery: any AdapterDiscoveryPort,
        defaultStore: any DefaultAdapterStorePort,
        isDemoModeEnabled: @escaping @MainActor () -> Bool,
        demoAdapter: AdapterDescriptor,
        connectRequested: @escaping @MainActor (AdapterDescriptor) -> Void
    ) {
        self.discovery = discovery
        self.defaultStore = defaultStore
        self.isDemoModeEnabled = isDemoModeEnabled
        self.demoAdapter = demoAdapter
        self.connectRequested = connectRequested
        state.defaultAdapter = defaultStore.load()
    }

    /// 責務: 操作を状態遷移へ変換します。
    func send(_ action: DeviceConnectionAction) {
        switch action {
        case .defaultAdapterLoadRequested:
            state.defaultAdapter = defaultStore.load()
            refreshDetection()
        case .discoverRequested:
            discover()
        case .discoveryCancelled:
            guard state.discovery == .discovering else { return }
            generation += 1
            state.discovery = .idle
        case .defaultAdapterSelected(let adapter):
            defaultStore.save(adapter)
            state.defaultAdapter = adapter
            refreshDetection()
        case .defaultAdapterCleared:
            defaultStore.save(nil)
            state.defaultAdapter = nil
            state.isDefaultAdapterDetected = false
        }
    }

    /// 責務: アダプターの出現通知をユーザーが受け入れたことを、接続要求として転送します。
    ///
    /// 構成時に `AdapterArrivalMonitoringPort.startMonitoring` の `onConnectRequested` へ渡します。
    func acceptArrival(_ adapter: AdapterDescriptor) {
        connectRequested(adapter)
    }

    /// 責務: 探索を1件だけ開始し、取り消されていない結果だけを反映します。
    private func discover() {
        guard state.discovery != .discovering else { return }
        generation += 1
        let token = generation
        state.discovery = .discovering
        Task {
            let outcome: Result<[AdapterDescriptor], AdapterDiscoveryError>
            do {
                outcome = .success(try await discovery.discoverAdapters())
            } catch let error as AdapterDiscoveryError {
                outcome = .failure(error)
            } catch {
                outcome = .failure(.failed)
            }
            guard token == generation else { return }
            let demo = isDemoModeEnabled() ? [demoAdapter] : []
            switch outcome {
            case .success(let found):
                state.adapters = found + demo
                state.discovery = .completed
            case .failure(let error):
                state.adapters = demo
                state.discovery = .failed(error)
            }
            refreshDetection()
        }
    }

    /// 責務: 既定アダプターが現在の探索結果に含まれるかを更新します。
    private func refreshDetection() {
        guard let adapter = state.defaultAdapter, state.discovery == .completed else {
            state.isDefaultAdapterDetected = false
            return
        }
        state.isDefaultAdapterDetected = state.adapters.contains { $0.id == adapter.id }
    }
}

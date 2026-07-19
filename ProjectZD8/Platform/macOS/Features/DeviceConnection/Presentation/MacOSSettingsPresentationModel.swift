#if os(macOS)
import Foundation
import Observation

/// macOS設定画面の操作をアダプター探索ユースケースと表示状態へ変換します。
@MainActor
@Observable
final class MacOSSettingsPresentationModel {
    /// 設定画面が描画する現在の表示状態です。
    var state: MacOSSettingsState

    /// 最新要求だけを通知するアダプター探索ユースケースです。
    @ObservationIgnored
    private let latestDiscovery: LatestAdapterDiscoveryUseCase

    /// デフォルト設定の保存、復元、検出照合を行うユースケースです。
    @ObservationIgnored
    private let defaultAdapterPreference: DefaultAdapterPreferenceUseCase

    /// 初期表示状態と探索ユースケースを注入してモデルを生成します。
    ///
    /// 責務: macOS設定画面の表示状態をアダプター探索とデフォルト設定のユースケースへ結び付けます。
    /// - Parameters:
    ///   - state: 設定画面の初期表示状態。
    ///   - latestDiscovery: 最新要求だけを通知するアダプター探索ユースケース。
    ///   - defaultAdapterPreference: デフォルト設定の保存、復元、検出照合を行うユースケース。
    init(
        state: MacOSSettingsState,
        latestDiscovery: LatestAdapterDiscoveryUseCase,
        defaultAdapterPreference: DefaultAdapterPreferenceUseCase
    ) {
        self.state = state
        self.latestDiscovery = latestDiscovery
        self.defaultAdapterPreference = defaultAdapterPreference
        restoreDefaultAdapter()
    }

    /// 設定画面から受け取った1件の操作を表示状態または探索へ反映します。
    ///
    /// 責務: 1件のmacOS設定操作を対応する表示状態遷移へ変換します。
    /// - Parameter action: 設定画面から通知された型付き操作。
    func send(_ action: MacOSSettingsAction) {
        switch action {
        case let .adapterSelectionRequested(slot):
            state.presentedAdapterSlot = slot
            startDiscovery()
        case let .adapterTransportModeSelected(mode):
            guard state.adapterTransportMode != mode else { return }
            state.adapterTransportMode = mode
            startDiscovery()
        case .adapterRefreshRequested:
            startDiscovery()
        case let .adapterCandidateSelected(adapter):
            state.inspectedAdapter = adapter
            state.hasAdapterAssignmentConflict = false
        case .inspectedAdapterConfirmed:
            guard
                let slot = state.presentedAdapterSlot,
                let adapter = state.inspectedAdapter
            else { return }
            guard AdapterAssignmentPolicy.conflictingRole(
                for: adapter,
                assigningTo: slot,
                assignments: state.selectedAdapters
            ) == nil else {
                state.hasAdapterAssignmentConflict = true
                return
            }
            state.selectedAdapters[slot] = adapter
            if slot == .primary {
                state.defaultAdapterPreference = defaultAdapterPreference.save(adapter: adapter)
            }
            closeAdapterSelection()
        case .inspectedAdapterDeclined:
            closeAdapterSelection()
        case .adapterDetailsDismissed:
            state.inspectedAdapter = nil
        case .adapterSelectionCancelled:
            closeAdapterSelection()
        case .adapterAttentionRequested:
            state.adapterAttentionSequence &+= 1
        case let .adapterAttentionConsumed(sequence):
            guard sequence == state.adapterAttentionSequence else { return }
            state.consumedAdapterAttentionSequence = sequence
        }
    }

    /// 保存済みデフォルト設定を読み込み、対応する接続方式で候補探索を開始します。
    ///
    /// 責務: 起動時のデフォルト設定を表示状態と自動照合探索へ反映します。
    private func restoreDefaultAdapter() {
        guard let preference = defaultAdapterPreference.load() else { return }
        state.defaultAdapterPreference = preference
        state.adapterTransportMode = preference.transportMode
        startDiscovery()
    }

    /// 現在選択されている接続方式で候補探索を開始します。
    ///
    /// 責務: 古い探索を破棄して現在の接続方式に対応する最新候補を表示状態へ反映します。
    private func startDiscovery() {
        let requestedMode = state.adapterTransportMode
        state.discoveredAdapters = []
        state.adapterDiscoveryStatus = .searching

        latestDiscovery.start(for: requestedMode) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case let .discovered(adapters):
                state.discoveredAdapters = adapters
                state.adapterDiscoveryStatus = .loaded
                synchronizeDetectedDefaultAdapter(with: adapters, for: requestedMode)
            case .unavailable, .failed:
                state.discoveredAdapters = []
                state.adapterDiscoveryStatus = .failed
                synchronizeDetectedDefaultAdapter(with: [], for: requestedMode)
            }
        }
    }

    /// 最新探索結果に合わせて保存済みデフォルト候補のプライマリー割当を同期します。
    ///
    /// 責務: 保存済みデフォルトと同じ接続方式の最新探索だけをプライマリー割当へ反映します。
    /// - Parameters:
    ///   - adapters: 最新探索で検出した候補一覧。
    ///   - mode: 最新探索で要求した接続方式。
    private func synchronizeDetectedDefaultAdapter(
        with adapters: [DiscoveredAdapter],
        for mode: AdapterTransportMode
    ) {
        guard let preference = state.defaultAdapterPreference else {
            state.selectedAdapters[.primary] = nil
            return
        }
        guard preference.transportMode == mode else { return }
        state.selectedAdapters[.primary] = defaultAdapterPreference.detectedAdapter(
            matching: preference,
            in: adapters
        )
    }

    /// 候補探索と関連モーダルを終了します。
    ///
    /// 責務: アダプター選択に伴う一時表示状態と進行中の探索を閉じます。
    private func closeAdapterSelection() {
        latestDiscovery.cancel()
        state.inspectedAdapter = nil
        state.hasAdapterAssignmentConflict = false
        state.presentedAdapterSlot = nil
    }
}
#endif

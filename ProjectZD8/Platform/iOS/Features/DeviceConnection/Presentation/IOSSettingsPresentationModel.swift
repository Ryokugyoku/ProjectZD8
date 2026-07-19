#if os(iOS)
import Foundation
import Observation

/// iOS設定画面の操作をBluetooth探索ユースケースと表示状態へ変換します。
@MainActor
@Observable
final class IOSSettingsPresentationModel {
    /// 設定画面が描画する現在の表示状態です。
    var state: IOSSettingsState

    /// 最新要求だけを通知するBluetooth候補探索ユースケースです。
    @ObservationIgnored
    private let latestDiscovery: LatestAdapterDiscoveryUseCase

    /// デフォルト設定の保存、復元、検出照合を行うユースケースです。
    @ObservationIgnored
    private let defaultAdapterPreference: DefaultAdapterPreferenceUseCase

    /// 初期表示状態と探索ユースケースを注入してモデルを生成します。
    ///
    /// 責務: iOS設定画面の表示状態をBluetooth探索とデフォルト設定のユースケースへ結び付けます。
    /// - Parameters:
    ///   - state: 設定画面の初期表示状態。
    ///   - latestDiscovery: 最新要求だけを通知するBluetooth候補探索ユースケース。
    ///   - defaultAdapterPreference: デフォルト設定の保存、復元、検出照合を行うユースケース。
    init(
        state: IOSSettingsState,
        latestDiscovery: LatestAdapterDiscoveryUseCase,
        defaultAdapterPreference: DefaultAdapterPreferenceUseCase
    ) {
        self.state = state
        self.latestDiscovery = latestDiscovery
        self.defaultAdapterPreference = defaultAdapterPreference
        restoreDefaultAdapter()
    }

    /// 設定画面から受け取った操作を表示状態またはBluetooth探索へ反映します。
    ///
    /// 責務: 1件のiOS設定操作を対応する表示状態遷移へ変換します。
    /// - Parameter action: 設定画面から通知された型付き操作。
    func send(_ action: IOSSettingsAction) {
        switch action {
        case let .adapterSelectionRequested(slot):
            state.presentedAdapterSlot = slot
            startBluetoothDiscovery()
        case .bluetoothRefreshRequested:
            startBluetoothDiscovery()
        case let .adapterCandidateSelected(adapter):
            state.inspectedAdapter = adapter
            state.hasAdapterAssignmentConflict = false
        case .inspectedAdapterConfirmed:
            guard let adapter = state.inspectedAdapter,
                  let slot = state.presentedAdapterSlot else { return }
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

    /// 保存済みデフォルト設定を読み込み、Bluetooth候補の自動探索を開始します。
    ///
    /// 責務: 起動時のデフォルト設定をiOS表示状態と自動照合探索へ反映します。
    private func restoreDefaultAdapter() {
        guard let preference = defaultAdapterPreference.load() else { return }
        state.defaultAdapterPreference = preference
        startBluetoothDiscovery()
    }

    /// 以前の探索を終了してBluetooth専用の最新探索を開始します。
    ///
    /// 責務: 最新世代のBluetooth候補または区別可能な利用不可理由だけをiOS表示状態へ反映します。
    private func startBluetoothDiscovery() {
        state.discoveredAdapters = []
        state.bluetoothDiscoveryStatus = .searching

        latestDiscovery.start(for: .bluetooth) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case let .discovered(adapters):
                state.discoveredAdapters = adapters
                state.bluetoothDiscoveryStatus = .loaded
                selectDetectedDefaultAdapter(from: adapters)
            case let .unavailable(error):
                state.discoveredAdapters = []
                state.bluetoothDiscoveryStatus = status(for: error)
            case .failed:
                state.discoveredAdapters = []
                state.bluetoothDiscoveryStatus = .failed
            }
        }
    }

    /// 検出結果に保存済みデフォルト候補が含まれる場合にプライマリーへ設定します。
    ///
    /// 責務: 最新Bluetooth探索結果から保存済みデフォルトと一致する候補を1件だけ自動選択します。
    /// - Parameter adapters: 最新Bluetooth探索で検出した候補一覧。
    private func selectDetectedDefaultAdapter(from adapters: [DiscoveredAdapter]) {
        guard
            let preference = state.defaultAdapterPreference,
            let adapter = defaultAdapterPreference.detectedAdapter(
                matching: preference,
                in: adapters
            )
        else { return }
        state.selectedAdapters[.primary] = adapter
    }

    /// Application探索エラーをiOS表示状態へ変換します。
    ///
    /// 責務: 1件の探索エラーを空一覧とは異なるiOS利用不可または失敗状態へ写像します。
    /// - Parameter error: Application探索境界から通知されたエラー。
    /// - Returns: 設定画面が描画する探索状態。
    private func status(for error: AdapterDiscoveryError) -> IOSBluetoothDiscoveryStatus {
        switch error {
        case .bluetoothPoweredOff:
            .unavailable(.poweredOff)
        case .bluetoothUnauthorized:
            .unavailable(.unauthorized)
        case .bluetoothUnsupported:
            .unavailable(.unsupported)
        case .transportUnsupported, .bluetoothStateUnavailable:
            .failed
        }
    }

    /// Bluetooth候補探索と関連モーダルを終了します。
    ///
    /// 責務: アダプター選択に伴う一時表示状態を閉じて以後の探索結果を無効化します。
    private func closeAdapterSelection() {
        latestDiscovery.cancel()
        state.inspectedAdapter = nil
        state.hasAdapterAssignmentConflict = false
        state.presentedAdapterSlot = nil
    }
}
#endif

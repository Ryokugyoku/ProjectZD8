#if os(iOS)
import SwiftUI

/// iOS専用の設定画面レイアウトを描画します。
///
/// 設定項目を追加する際は、アカウント同期対象に含めるか、
/// Connection固有の同期除外対象にするかを併せて検討する必要があります。
/// 画面ルートは部品の配置・シート・オーバーレイ・Action 送出だけを持ち、各カードは `IOSSettings` 接頭辞の部品 View に分けています。
struct IOSSettingsView: View {
    /// アクセシビリティ設定で動きを抑える必要があるかどうかです。
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// アダプター設定カードの振動アニメーション進行値です。
    @State private var adapterAttentionProgress: CGFloat = 0

    /// このViewが最後に処理した注目要求番号です。
    @State private var handledAdapterAttentionSequence: UInt = 0

    /// 注目要求を強調表示すべきかの判定です。
    private let attentionPolicy = AdapterSettingsAttentionPolicy()

    /// 設定画面に表示する現在のConnection選択状態です。
    let state: IOSSettingsState

    /// 設定画面に表示するアカウント同期対象の表示設定と自動アップロード設定です。
    let accountSettings: AccountSettings

    /// 設定画面のConnection操作をAppShellへ通知するクロージャです。
    let send: (IOSSettingsAction) -> Void

    /// 表示設定と自動アップロード設定の操作をアカウント設定モデルへ通知するクロージャです。
    let sendAccountSettingsAction: (AccountSettingsAction) -> Void

    /// 車両検知時の記録開始方法の区画に表示する内容です。
    let automaticRecordingSection: AutomaticRecordingSettingsSection

    /// 記録開始方法の操作を自動記録設定モデルへ通知するクロージャです。
    let sendAutomaticRecordingAction: (AutomaticRecordingPreferenceAction) -> Void

    /// 「エンジン停止とみなす時間」の区画に表示する内容です。
    let vehicleOffSection: VehicleOffDetectionSettingsSection

    /// 「エンジン停止とみなす時間」の操作を設定モデルへ通知するクロージャです。
    let sendVehicleOffAction: (VehicleOffDetectionDelayAction) -> Void

    /// Authenticationが管理するアカウント削除の現在段階です。
    let accountDeletionPhase: AccountDeletionPhase

    /// Authenticationが保持する直近のアカウント削除失敗です。
    let accountDeletionFailure: AccountDeletionFailure?

    /// アカウント削除の型付き操作をAuthenticationへ通知します。
    let sendAuthenticationAction: (AuthenticationAction) -> Void

    /// iPhoneの縦方向操作に合わせた設定スクロール領域を提供します。
    ///
    /// 責務: アカウント同期対象設定とConnection固有設定を区別したiOS設定レイアウトとして描画します。
    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                cards
                    .padding(.horizontal, IOSSettingsMetrics.screenHorizontalPadding)
                    .padding(.top, IOSSettingsMetrics.screenTopPadding)
                    .padding(.bottom, IOSSettingsMetrics.screenBottomPadding)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                presentAdapterAttentionIfNeeded(
                    sequence: state.adapterAttentionSequence,
                    isPending: state.hasPendingAdapterAttention,
                    scrollProxy: scrollProxy
                )
            }
            .onChange(of: state.adapterAttentionSequence) { _, sequence in
                presentAdapterAttentionIfNeeded(
                    sequence: sequence,
                    isPending: state.hasPendingAdapterAttention,
                    scrollProxy: scrollProxy
                )
            }
        }
        .sheet(
            isPresented: Binding(
                get: { state.presentedAdapterSlot != nil },
                set: { isPresented in
                    if !isPresented { send(.adapterSelectionCancelled) }
                }
            )
        ) {
            if let slot = state.presentedAdapterSlot {
                IOSAdapterSelectionView(slot: slot, state: state, send: send)
                    .environment(\.locale, Locale(identifier: accountSettings.language.localeIdentifier))
            }
        }
        .overlay {
            IOSAccountDeletionFlowView(
                phase: accountDeletionPhase,
                failure: accountDeletionFailure,
                send: sendAuthenticationAction
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-settings-screen")
    }

    /// 設定カードを上から順に並べた列です。
    private var cards: some View {
        LazyVStack(alignment: .leading, spacing: IOSSettingsMetrics.screenSpacing) {
            IOSSettingsHeader()
            IOSSettingsLanguageCard(language: accountSettings.language) {
                sendAccountSettingsAction(.languageSelected($0))
            }
            IOSSettingsAppearanceCard(appearance: accountSettings.appearance) {
                sendAccountSettingsAction(.appearanceSelected($0))
            }
            IOSSettingsAdapterCard(
                selectedAdapters: state.selectedAdapters,
                defaultAdapterPreference: state.defaultAdapterPreference,
                attentionProgress: accessibilityReduceMotion ? 0 : adapterAttentionProgress
            ) {
                send(.adapterSelectionRequested($0))
            }
            IOSSettingsAutomaticRecordingCard(section: automaticRecordingSection) {
                sendAutomaticRecordingAction(.settingsChoiceSelected($0))
            }
            IOSSettingsVehicleOffCard(section: vehicleOffSection) {
                sendVehicleOffAction(.delaySelected($0))
            }
            IOSSettingsUploadCard(isEnabled: accountSettings.automaticSessionUploadEnabled) {
                sendAccountSettingsAction(.automaticSessionUploadChanged($0))
            }
            IOSSettingsAccountDeletionCard {
                sendAuthenticationAction(.accountDeletionRequested)
            }
        }
    }

    /// HOMEの「アダプターを設定」ボタン由来で未消費の注目要求がある場合だけ設定カードへスクロールして振動させます。
    ///
    /// 責務: 判定 `AdapterSettingsAttentionPolicy` が許す時だけ、要求を消費済みにしてスクロールと振動を始めます。
    /// 「アダプターを設定」ボタンを押すたびに遷移直後の1回だけを強調し、通常の手動遷移では再表示しません。
    /// - Parameters:
    ///   - sequence: 処理対象の注目要求番号。
    ///   - isPending: 直前の「アダプターを設定」ボタン押下による未消費要求が残っているかどうか。
    ///   - scrollProxy: アダプター設定カードを表示領域へ移動するスクロール操作境界。
    private func presentAdapterAttentionIfNeeded(
        sequence: UInt,
        isPending: Bool,
        scrollProxy: ScrollViewProxy
    ) {
        guard attentionPolicy.shouldPresent(
            sequence: sequence,
            isPending: isPending,
            handledSequence: handledAdapterAttentionSequence
        ) else { return }
        handledAdapterAttentionSequence = sequence
        send(.adapterAttentionConsumed(sequence))
        withAnimation(.snappy(duration: IOSSettingsMetrics.attentionScrollDuration)) {
            scrollProxy.scrollTo(IOSSettingsAdapterCard.scrollID, anchor: .center)
        }
        adapterAttentionProgress = 0
        guard !accessibilityReduceMotion else { return }
        withAnimation(.linear(duration: IOSSettingsMetrics.attentionShakeDuration)) {
            adapterAttentionProgress = 1
        }
    }
}
#endif

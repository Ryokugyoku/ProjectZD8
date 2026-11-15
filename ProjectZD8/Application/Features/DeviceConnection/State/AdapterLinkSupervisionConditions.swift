import Foundation

/// 監視の遷移を決めるときに参照する、状態以外の現在の条件です。
nonisolated struct AdapterLinkSupervisionConditions: Equatable, Sendable {
    /// 監視が `start()` 済みで `stop()` されていないかどうかです。
    let isSupervisionStarted: Bool

    /// ユーザーがサインイン済みかどうかです。
    let isSignedIn: Bool

    /// 現在保存されている既定アダプター設定です。未設定の場合は `nil` です。
    let defaultAdapterPreference: DefaultAdapterPreference?

    /// 常駐リンクを開始したときの接続対象設定です。リンクを開始していない場合は `nil` です。
    let linkPreference: DefaultAdapterPreference?

    /// このイベントを処理する直前に把握していたリンク状態です。
    let linkState: AdapterLinkState

    /// このイベントを処理する時点の現在時刻です。
    let now: Date

    /// 常駐リンク以外の経路(手動接続)がアダプターを使っている最中かどうかです。`true` の間は初期化・車両確認を始めません。
    let isExternalAdapterUseActive: Bool

    /// 遷移の参照条件を固定して生成します。
    ///
    /// 責務: 1件のイベント処理で参照する条件を不変値へまとめます。
    /// - Parameters:
    ///   - isSupervisionStarted: 監視が開始済みか。
    ///   - isSignedIn: サインイン済みか。
    ///   - defaultAdapterPreference: 保存済みの既定アダプター設定。
    ///   - linkPreference: リンクを開始したときの接続対象設定。
    ///   - linkState: 処理直前に把握していたリンク状態。
    ///   - now: 現在時刻。
    ///   - isExternalAdapterUseActive: 手動接続がアダプターを使っている最中か。既定は `false`。
    init(
        isSupervisionStarted: Bool,
        isSignedIn: Bool,
        defaultAdapterPreference: DefaultAdapterPreference?,
        linkPreference: DefaultAdapterPreference?,
        linkState: AdapterLinkState,
        now: Date,
        isExternalAdapterUseActive: Bool = false
    ) {
        self.isSupervisionStarted = isSupervisionStarted
        self.isSignedIn = isSignedIn
        self.defaultAdapterPreference = defaultAdapterPreference
        self.linkPreference = linkPreference
        self.linkState = linkState
        self.now = now
        self.isExternalAdapterUseActive = isExternalAdapterUseActive
    }

    /// 稼働条件を満たす場合にリンクの接続対象とすべき既定アダプター設定です。
    ///
    /// 責務: 「開始済み・サインイン済み・既定アダプターがBLE」の3条件を判定します。
    /// 満たさない場合は `nil` です。
    var operatingPreference: DefaultAdapterPreference? {
        guard isSupervisionStarted, isSignedIn,
              let defaultAdapterPreference,
              defaultAdapterPreference.connectionTransport == .bluetoothLowEnergy else {
            return nil
        }
        return defaultAdapterPreference
    }

    /// 稼働中のリンクが `ready` で、監視から初期化を始められるかどうかです。
    ///
    /// 責務: リンク開始済みかつ直前のリンク状態が `ready` であることを判定します。
    var isLinkReady: Bool {
        linkPreference != nil && linkState == .ready
    }
}

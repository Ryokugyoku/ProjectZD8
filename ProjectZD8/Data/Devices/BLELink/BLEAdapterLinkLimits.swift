#if os(iOS) || os(macOS)
/// 常駐BLEリンクの再試行と探索待機の上限値です。
///
/// 既定値の根拠:
/// - `maximumConsecutiveReconnects = 5`: `connect` はタイムアウトのない保留接続なので、圏外のアダプターは回数を消費しません。
///   回数を消費するのは接続失敗・切断・探索失敗など明示的な失敗だけです。エンジン始動時の電圧降下による一時的な切断が
///   数回続いても復帰できる幅を残しつつ、ペアリング不整合やファームウェア異常のような恒常的な失敗で
///   接続と切断を際限なく繰り返さないよう、5回で止めます。
/// - `discoveryStepTimeout = 10秒`: 既存の `AppleCoreBluetoothOBDTransport` が読取待機に使う10秒と揃えます。
///   Service・Characteristic探索とNotify有効化はそれぞれ通常1秒未満で完了し、ATTの30秒タイムアウトより十分短く切り上げます。
nonisolated struct BLEAdapterLinkLimits: Equatable, Sendable {
    /// 既定の上限値です。
    static let standard = BLEAdapterLinkLimits(maximumConsecutiveReconnects: 5, discoveryStepTimeout: .seconds(10))

    /// `ready` に到達しないまま再接続してよい連続回数です。これを超える失敗で終端の `retryLimitExceeded` になります。
    let maximumConsecutiveReconnects: Int

    /// 探索の各段階(Service探索、Characteristic探索、Notify有効化、キャンセル完了)を待つ上限時間です。
    let discoveryStepTimeout: Duration

    /// 上限値を生成します。
    ///
    /// 責務: 負の値を0へ丸めて上限値を固定します。
    /// - Parameters:
    ///   - maximumConsecutiveReconnects: 連続再接続の上限回数。負の値は0(再接続しない)として扱います。
    ///   - discoveryStepTimeout: 探索の各段階の待機上限。負の値は0(直ちに上限超過)として扱います。
    init(maximumConsecutiveReconnects: Int, discoveryStepTimeout: Duration) {
        self.maximumConsecutiveReconnects = max(0, maximumConsecutiveReconnects)
        self.discoveryStepTimeout = max(.zero, discoveryStepTimeout)
    }
}
#endif

#if os(iOS) || os(macOS)
/// 常駐BLEリンクの再試行・探索待機・書き込み完了待ちの上限値です。
///
/// 既定値の根拠:
/// - `maximumConsecutiveReconnects = 5`: `connect` はタイムアウトのない保留接続なので、圏外のアダプターは回数を消費しません。
///   回数を消費するのは接続失敗・切断・探索失敗など明示的な失敗だけです。エンジン始動時の電圧降下による一時的な切断が
///   数回続いても復帰できる幅を残しつつ、ペアリング不整合やファームウェア異常のような恒常的な失敗で
///   接続と切断を際限なく繰り返さないよう、5回で止めます。
/// - `discoveryStepTimeout = 10秒`: 既存の `AppleCoreBluetoothOBDTransport` が読取待機に使う10秒と揃えます。
///   Service・Characteristic探索とNotify有効化はそれぞれ通常1秒未満で完了し、ATTの30秒タイムアウトより十分短く切り上げます。
/// - `writeCompletionTimeout = 10秒`: 探索段階と同じ水準です。応答あり書き込みの完了通知・応答なし書き込みの送信可能通知は
///   通常数十ミリ秒で届くため、10秒届かなければリンク障害として接続をやり直します。
nonisolated struct BLEAdapterLinkLimits: Equatable, Sendable {
    /// 既定の上限値です。
    static let standard = BLEAdapterLinkLimits(
        maximumConsecutiveReconnects: 5,
        discoveryStepTimeout: .seconds(10),
        writeCompletionTimeout: standardWriteCompletionTimeout
    )

    /// 書き込み完了待ちの既定の上限時間です。
    static let standardWriteCompletionTimeout: Duration = .seconds(10)

    /// `ready` に到達しないまま再接続してよい連続回数です。これを超える失敗で終端の `retryLimitExceeded` になります。
    let maximumConsecutiveReconnects: Int

    /// 探索の各段階(Service探索、Characteristic探索、Notify有効化、キャンセル完了)を待つ上限時間です。
    let discoveryStepTimeout: Duration

    /// 書き込みが進まない(応答ありの完了通知、応答なしの送信可能通知が届かない)まま待つ上限時間です。
    let writeCompletionTimeout: Duration

    /// 上限値を生成します。
    ///
    /// 責務: 負の値を0へ丸めて上限値を固定します。
    /// - Parameters:
    ///   - maximumConsecutiveReconnects: 連続再接続の上限回数。負の値は0(再接続しない)として扱います。
    ///   - discoveryStepTimeout: 探索の各段階の待機上限。負の値は0(直ちに上限超過)として扱います。
    ///   - writeCompletionTimeout: 書き込みが進まないまま待つ上限。負の値は0(直ちに上限超過)として扱います。
    init(
        maximumConsecutiveReconnects: Int,
        discoveryStepTimeout: Duration,
        writeCompletionTimeout: Duration = BLEAdapterLinkLimits.standardWriteCompletionTimeout
    ) {
        self.maximumConsecutiveReconnects = max(0, maximumConsecutiveReconnects)
        self.discoveryStepTimeout = max(.zero, discoveryStepTimeout)
        self.writeCompletionTimeout = max(.zero, writeCompletionTimeout)
    }
}
#endif

#if os(iOS) || os(macOS)
/// `ready` に到達しないまま続いた失敗を数え、再接続してよいかを判定します。
nonisolated struct BLEAdapterLinkRetryCounter: Equatable, Sendable {
    /// 再接続してよい連続回数の上限です。
    let maximumConsecutiveReconnects: Int

    /// `ready` 到達後に続いている失敗の回数です。
    private(set) var consecutiveFailures = 0

    /// 上限回数を固定して生成します。
    ///
    /// 責務: 再接続上限を負にならない値で保持します。
    /// - Parameter maximumConsecutiveReconnects: 再接続してよい連続回数。負の値は0として扱います。
    init(maximumConsecutiveReconnects: Int) {
        self.maximumConsecutiveReconnects = max(0, maximumConsecutiveReconnects)
    }

    /// 失敗を1回記録し、再接続してよいかを返します。
    ///
    /// 責務: 連続失敗数を進め、上限以内なら再接続可と判定します。
    /// - Returns: 連続失敗数が上限以下なら `true`(再接続する)。上限を超えたら `false`(終端)。
    mutating func recordFailure() -> Bool {
        consecutiveFailures += 1
        return consecutiveFailures <= maximumConsecutiveReconnects
    }

    /// `ready` 到達または再開始で連続失敗数を0へ戻します。
    ///
    /// 責務: 連続失敗数を初期化します。
    mutating func reset() {
        consecutiveFailures = 0
    }
}
#endif

/// 走行ルートの要約を表示用に整形した文字列です。
nonisolated struct DrivingRouteSummaryText: Equatable, Sendable {
    /// 長さの文字列です。
    let lengthText: String
    /// 記録できた時間の文字列です。
    let recordedDurationText: String
    /// 記録できた割合の文字列です。割合が無い時は "—" です。
    let coverageText: String
}

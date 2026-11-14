/// 受信監視フィルターのコマンド列を生成できなかった理由です。
nonisolated enum ELM327MonitorFilterCommandBuildError: Error, Equatable, Sendable {
    /// 絞り込むCAN IDが1件も指定されませんでした。
    case emptyIdentifiers
    /// 29bit範囲(`0x1FFFFFFF`)を超えるCAN IDが含まれていました。
    case identifierOutOfRange
    /// 11bit IDと29bit IDが混在していました。
    case mixedIdentifierWidths
    /// チップ系統が不明で、使えるフィルターコマンドを決められませんでした。
    case unsupportedChipFamily
}

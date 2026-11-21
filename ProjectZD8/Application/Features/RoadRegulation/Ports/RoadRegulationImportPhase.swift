import Foundation

/// 取り込みの段階と進み具合です。
nonisolated enum RoadRegulationImportPhase: Equatable, Sendable {
    /// 残りの掃除などの準備中。
    case preparing
    /// 一覧を取得中。
    case fetchingCatalog
    /// ZIP をダウンロード中。
    case downloading(RoadRegulationTransferProgress)
    /// ZIP を読んで保存中。
    case importing(RoadRegulationArchiveReadProgress, importedCount: Int)
    /// 新しい版を有効にしている。
    case activating
    /// 古い版と一時ファイルを掃除している。
    case cleaningUp
}

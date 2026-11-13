/// 分析画面の読み込み段階です。
nonisolated enum AnalysisPhase: Equatable, Sendable {
    /// 何も読み込んでいない。
    case idle
    /// 車両とセッションの一覧を読み込み中。
    case loadingCatalog
    /// セッションのRawを変換してデータセットを作成中。
    case building(SessionID)
    /// RawがiCloud上にだけある。ダウンロードしてよいか確認を待っている。
    case awaitingDownloadConsent(SessionID)
    /// iCloudからRawをダウンロード中(0〜1)。
    case downloading(SessionID, progress: Double)
    /// 長期傾向を集計中。
    case buildingTrend
    /// 読み込みが完了し、表示できる。
    case ready
    /// 失敗した。
    case failed(AnalysisFailure)
}

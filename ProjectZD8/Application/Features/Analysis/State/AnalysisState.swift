/// 分析画面の表示状態です。
nonisolated struct AnalysisState: Equatable, Sendable {
    /// 同時に読み込める比較セッション数の上限です。
    static let maximumLoadedSessions = 3

    /// ワークベンチの表示言語(`ja` / `en` / `es`)です。
    var languageCode: String
    /// 選択できる車両です。
    var vehicles: [AnalysisVehicleOption] = []
    /// 選択中の車両です。
    var selectedVehicleID: VehicleID?
    /// 選択中の車両のセッション(新しい順)です。
    var sessionOptions: [AnalysisSessionOption] = []
    /// ワークベンチへ渡し済みのセッションです。先頭が主セッションです。
    var loadedSessions: [AnalysisLoadedSession] = []
    var phase: AnalysisPhase = .idle
    var trend: AnalysisTrendStatus = .idle
    /// セッション選択UIを開くべき場合の目的です。
    var pickerPurpose: AnalysisPickerPurpose?
    /// プラットフォームが保存・共有すべき書き出しです。
    var pendingExport: AnalysisExportRequest?
    /// ワークベンチへ送るべき内容が変わるたびに増えます。
    var contentRevision = 0

    /// 責務: 表示言語を指定して初期状態を生成します。
    init(languageCode: String) {
        self.languageCode = languageCode
    }

    /// 同時読み込みの上限に達しているかどうかです。
    var isAtSessionLimit: Bool { loadedSessions.count >= Self.maximumLoadedSessions }
}

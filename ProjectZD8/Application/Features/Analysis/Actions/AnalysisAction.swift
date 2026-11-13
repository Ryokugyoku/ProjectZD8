import Foundation

/// 分析画面から送る操作です。
nonisolated enum AnalysisAction: Equatable, Sendable {
    /// 画面が現れた。車両一覧を読み込む。
    case appeared
    /// 車両を選んだ。その車両のセッション一覧を読み込む。
    case selectVehicle(VehicleID)
    /// セッションを開く(表示中のものと置き換える)。
    case openSession(SessionID)
    /// 比較用にセッションを追加する(最大3件)。
    case addComparisonSession(SessionID)
    /// 読み込み済みのセッションを外す。
    case removeSession(SessionID)
    /// iCloudからのRawのダウンロードを承諾した。
    case confirmDownload
    /// iCloudからのRawのダウンロードを断った。
    case declineDownload
    /// 長期傾向の集計を要求する。
    case requestTrend(includeDemo: Bool)
    /// セッション選択UIを開くよう要求する。
    case requestSessionPicker(AnalysisPickerPurpose)
    /// セッション選択UIを閉じた。
    case dismissSessionPicker
    /// Webから書き出し内容が届いた。
    case receiveExport(AnalysisExportRequest)
    /// 書き出し内容を保存・共有し終えた(または破棄した)。
    case finishExport
    /// 失敗表示を閉じる。
    case dismissFailure
}

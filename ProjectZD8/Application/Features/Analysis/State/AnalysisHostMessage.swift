import Foundation

/// ネイティブからWebワークベンチへ送る、現在の状態の写しです。
nonisolated struct AnalysisHostMessage: Codable, Equatable, Sendable {
    /// ワークベンチへ渡す1セッションです。
    struct Session: Codable, Equatable, Sendable {
        let id: String
        let datasetPath: String
    }

    let type: String
    let language: String
    let sessions: [Session]
    /// 長期傾向が使える時のデータパスです。
    let trendPath: String?
    /// 読み込み段階(`idle`、`loading`、`downloading`、`ready`、`failed`)です。
    let phase: String
    /// ダウンロード進捗(0〜1)です。ダウンロード中以外は `nil` です。
    let progress: Double?
    /// 失敗の種別名です。失敗していなければ `nil` です。
    let failure: String?

    /// 責務: 画面状態をワークベンチ向けの設定メッセージへ写します。
    init(state: AnalysisState) {
        type = "configure"
        language = state.languageCode
        sessions = state.loadedSessions.map { Session(id: $0.id.rawValue.uuidString, datasetPath: $0.datasetPath) }
        if case .ready(let vehicleID) = state.trend {
            trendPath = AnalysisDatasetStore.trendPath(for: vehicleID)
        } else {
            trendPath = nil
        }
        switch state.phase {
        case .idle, .awaitingDownloadConsent: phase = "idle"
        case .loadingCatalog, .building, .buildingTrend: phase = "loading"
        case .downloading: phase = "downloading"
        case .ready: phase = "ready"
        case .failed: phase = "failed"
        }
        if case .downloading(_, let value) = state.phase { progress = value } else { progress = nil }
        if case .failed(let failure) = state.phase { self.failure = failure.kind } else { failure = nil }
    }

    /// 責務: メッセージをJSON文字列へ符号化します。
    func jsonString() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let string = String(data: data, encoding: .utf8) else { throw AnalysisFailure.encoding }
        return string
    }
}

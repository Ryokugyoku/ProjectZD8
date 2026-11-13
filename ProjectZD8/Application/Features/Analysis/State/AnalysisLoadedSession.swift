import Foundation

/// ワークベンチへ渡し済みの1セッションです。
nonisolated struct AnalysisLoadedSession: Identifiable, Equatable, Sendable {
    let id: SessionID
    /// データセットJSONの相対パスです。
    let datasetPath: String
    let vehicleName: String
    let startedAt: Date
    let isDemo: Bool
}

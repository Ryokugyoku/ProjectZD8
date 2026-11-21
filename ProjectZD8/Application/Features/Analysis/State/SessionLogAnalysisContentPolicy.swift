import Foundation

/// セッション解析の状態から、画面の本文に出す内容を決めます。SwiftUI に依存しない純粋型です。
///
/// iOS と macOS の解析画面で共有します。
nonisolated struct SessionLogAnalysisContentPolicy: Sendable {
    /// 判定を生成します。
    ///
    /// 責務: 状態を持たない判定を作ります。
    init() {}

    /// 解析状態に対応する本文の内容を返します。
    ///
    /// 責務: 読込段階と時系列の有無を、取得中・初回読込中・失敗・空・解析結果のいずれかへ変換します。
    /// - Parameter state: 画面へ公開されている解析状態。
    /// - Returns: 取得中なら取得率付きの `downloading`。時系列が空なら段階に応じた状態。
    ///   それ以外は読込中だけ進捗を出す `results`。
    func content(for state: SessionLogAnalysisState) -> SessionLogAnalysisContent {
        let hasTimeline = !state.timeline.isEmpty
        switch state.phase {
        case .downloading: return .downloading(progress: state.downloadProgress ?? 0)
        case .loading: return hasTimeline ? .results(showsProgress: true) : .initialLoading
        case .failed: return hasTimeline ? .results(showsProgress: false) : .failedWithoutData
        case .loaded: return hasTimeline ? .results(showsProgress: false) : .empty
        case .idle, .awaitingDownloadConfirmation: return .results(showsProgress: false)
        }
    }
}

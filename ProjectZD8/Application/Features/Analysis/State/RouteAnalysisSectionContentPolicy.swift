/// 解析の走行ルートの状態から、地図の場所に出す内容を決めます。SwiftUI に依存しない純粋型です。
///
/// iOS と macOS の解析画面で共有します。
nonisolated struct RouteAnalysisSectionContentPolicy: Sendable {
    /// 判定を生成します。
    ///
    /// 責務: 状態を持たない判定を作ります。
    init() {}

    /// 走行ルートの状態に対応する地図の場所の内容を返します。
    ///
    /// 責務: 読み込みの段階と地図の内容の有無を、読み込み中・理由・失敗・地図のいずれかへ変換します。
    /// - Parameter state: 画面へ公開されている走行ルートの状態。
    /// - Returns: `ready` で地図の内容がある時だけ `ready`。`ready` でも内容がまだ無ければ読み込み中。
    func content(for state: RouteAnalysisState) -> RouteAnalysisSectionContent {
        switch state.phase {
        case .idle, .waitingForAccount:
            return .loading(isLoadingRoute: false)
        case .loading:
            return .loading(isLoadingRoute: true)
        case .ready:
            guard let layers = state.layers else { return .loading(isLoadingRoute: false) }
            return .ready(layers)
        case .unavailable(let reasonKey, let systemImage):
            return .unavailable(reasonKey: reasonKey, systemImage: systemImage)
        case .failed(let messageKey, let isRetryable):
            return .failed(messageKey: messageKey, isRetryable: isRetryable)
        }
    }
}

/// 色分けの選択肢1つです。
nonisolated struct RouteAnalysisColorSourceOption: Identifiable, Equatable, Sendable {
    /// 選択肢が指す色分けの元です。
    let source: RouteAnalysisColorSource
    /// 選択肢の名前のローカライズキーです。
    let titleKey: String
    /// 選べる時に `true` です。
    let isEnabled: Bool
    /// 選べない理由のローカライズキーです。選べる時は `nil` です。
    let disabledReasonKey: String?

    /// 選択肢を識別する値(色分けの元)です。
    var id: RouteAnalysisColorSource {
        source
    }
}

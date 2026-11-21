/// 色分けの元の選択肢と選択から、切替の部品に出す見出しと「選べない」案内を決めます。SwiftUI に依存しない純粋型です。
///
/// iOS と macOS の解析画面で共有します。
nonisolated struct RouteAnalysisColorSourceMenuContent: Equatable, Sendable {
    /// 色分けの元の選択肢(表示順)です。
    let options: [RouteAnalysisColorSourceOption]
    /// 選んでいる色分けの元です。
    let selectedSource: RouteAnalysisColorSource?

    /// 選択肢と選択を受け取って作ります。
    ///
    /// 責務: 受け取った選択肢と選択を保持します。
    /// - Parameters:
    ///   - options: 色分けの元の選択肢。
    ///   - selectedSource: 選んでいる色分けの元。
    init(options: [RouteAnalysisColorSourceOption], selectedSource: RouteAnalysisColorSource?) {
        self.options = options
        self.selectedSource = selectedSource
    }

    /// 切替の部品を出すかです。選択肢が1つ以上ある時に `true` です。
    var isVisible: Bool {
        !options.isEmpty
    }

    /// 選んでいる選択肢の名前のローカライズキーです。選んでいない時・選択肢に無い時は `nil` です。
    var selectedTitleKey: String? {
        options.first { $0.source == selectedSource }?.titleKey
    }

    /// 選べない選択肢の名前のローカライズキー(表示順)です。
    var unavailableTitleKeys: [String] {
        options.filter { !$0.isEnabled }.map(\.titleKey)
    }

    /// 選べない理由のローカライズキーです。選べない選択肢のうち最初に理由を持つものの理由で、無ければ `nil` です。
    var unavailableReasonKey: String? {
        options.first { !$0.isEnabled && $0.disabledReasonKey != nil }?.disabledReasonKey
    }

    /// 選択肢が今選ばれているかを返します。
    ///
    /// 責務: 選択肢の色分けの元が選択と一致するかを判定します。
    /// - Parameter option: 判定する選択肢。
    /// - Returns: 選ばれていれば `true`。
    func isSelected(_ option: RouteAnalysisColorSourceOption) -> Bool {
        option.source == selectedSource
    }
}

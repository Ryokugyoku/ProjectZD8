import Foundation

/// 解析画面の交通規制の照合への操作です。
enum SessionRoadRegulationReviewAction: Equatable {
    /// サインイン中のアカウントが変わりました(サインアウトでは `nil`)。
    case accountIdentifierChanged(String?)
    /// 照合を始められるかどうかが変わりました(画面ルートが `onChange(initial: true)` で送ります)。
    case readinessChanged(ConnectionSessionID, SessionRoadRegulationReviewReadiness)
    /// 一覧の絞り込みを選びました。
    case filterChanged(SessionRoadRegulationReviewFilter)
    /// 一覧の行を選びました(同じ行をもう一度選ぶと解除します)。
    case rowSelected(Int)
    /// 失敗した照合の再試行が求められました。
    case retryRequested
    /// 照合の表示を閉じました。
    case dismissed
}

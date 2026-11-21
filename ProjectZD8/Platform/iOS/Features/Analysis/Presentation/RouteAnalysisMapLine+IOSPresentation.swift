#if os(iOS)
import SwiftUI

/// 解析の色の区間の線を、iPhone の地図部品が描く線の契約へ対応づけます。
extension RouteAnalysisMapLine: RouteMapLineContent {
    /// iPhone の解析の地図で描く線の見た目です。
    ///
    /// 責務: 色と太さは分類から取り、強調する線は太くし、概略の位置の区間か値なしの区間を破線にします。
    var appearance: RouteMapLineAppearance {
        let extraWidth = isEmphasized ? IOSRouteAnalysisMetrics.emphasizedExtraWidth : 0
        return RouteMapLineAppearance(
            color: category.color,
            width: category.lineWidth + extraWidth,
            isDashed: isApproximate || category.isDashed
        )
    }
}
#endif

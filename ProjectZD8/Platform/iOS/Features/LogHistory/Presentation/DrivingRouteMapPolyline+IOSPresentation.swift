#if os(iOS)
import SwiftUI

/// 走行ルートの折れ線を、iPhone の地図部品が描く線の契約へ対応づけます。
extension DrivingRouteMapPolyline: RouteMapLineContent {
    /// iPhone の地図で描く線の見た目です。
    ///
    /// 責務: アクセント色のシアンと既定の太さにし、概略の位置の区間だけ破線にします。
    var appearance: RouteMapLineAppearance {
        RouteMapLineAppearance(color: .cyan, width: RouteMapMetrics.lineWidth, isDashed: isApproximate)
    }
}
#endif

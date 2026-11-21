#if os(macOS)
import SwiftUI

/// 走行ルートの折れ線を、Shared の地図部品の線の契約へ接続します。
///
/// 線はアクセント色のシアンで描き、概略の位置の区間だけ破線にします。
extension DrivingRouteMapPolyline: RouteMapLineContent {
    /// macOS のセッション詳細の地図に描く線の見た目です。
    var appearance: RouteMapLineAppearance {
        RouteMapLineAppearance(color: .cyan, width: RouteMapMetrics.lineWidth, isDashed: isApproximate)
    }
}
#endif

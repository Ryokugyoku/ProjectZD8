/// 地図部品で利用者に許す操作です。
enum RouteMapInteraction: Equatable {
    /// 操作できない地図(interactionModes が空)。
    case fixed
    /// 移動と拡大縮小ができる地図(interactionModes が pan と zoom)。
    case explorable
}

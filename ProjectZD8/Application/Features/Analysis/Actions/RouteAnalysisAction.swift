import Foundation

/// 解析の走行ルートの表示(色分け・グラフ・連動)への操作です。
enum RouteAnalysisAction: Equatable {
    /// サインイン中のアカウントが変わりました(サインアウトでは `nil`)。
    case accountIdentifierChanged(String?)
    /// ルートの表示を最初に開きました。
    case sessionShown(ConnectionSession)
    /// 解析の時系列を読み終えました(解析の root View が `.loaded` の時に送ります)。
    case timelineLoaded(ConnectionSessionID, [SessionLogAnalysisState.TimelineSample])
    /// 色分けの元を選びました。
    case colorSourceSelected(RouteAnalysisColorSource)
    /// グラフで時刻をなぞりました(離すと `nil`)。
    case timeSelected(Date?)
    /// 地図の座標を選びました(逆方向の連動。任意)。
    case mapCoordinateSelected(GeoCoordinate)
    /// 重ね合わせが変わりました(5c が使います)。
    case overlaysChanged([RouteAnalysisOverlay])
    /// 失敗した読み込みの再試行が求められました。
    case retryRequested
    /// ルートの表示を閉じました。
    case dismissed
}

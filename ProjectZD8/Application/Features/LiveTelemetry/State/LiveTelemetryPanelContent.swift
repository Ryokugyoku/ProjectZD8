/// ホームに差し込むリアルタイム表示パネルの表示内容です。
///
/// iOSとmacOSで共通の判定です。接続中でない時は古い値を出さず、失敗の理由と再試行だけを出します。
struct LiveTelemetryPanelContent: Equatable {
    /// 状態バナーです。表示する状態がなければ `nil` です。
    let banner: LiveTelemetryStatusBanner?
    /// 現在値を表示するかどうかです。接続中で、サンプルが1件以上ある時だけ `true` です。
    let showsSamples: Bool
    /// 再試行操作を表示するかどうかです。失敗中で、再試行に必要な接続先と車両がそろう時だけ `true` です。
    let showsRetry: Bool
    /// 応答したPIDの件数です。接続中で1件以上ある時だけ値を持ちます。
    let respondingPIDCount: Int?
    /// サンプルの振り分け結果です。
    let groups: LiveTelemetrySampleGroups
    /// パネルに描くものが何もないかどうかです。
    let isEmpty: Bool

    /// リアルタイム表示の状態からパネルの表示内容を生成します。
    ///
    /// 責務: 取得状態をバナー・現在値・再試行・応答件数の表示可否へ変換します。
    /// - Parameter state: 現在のリアルタイム表示状態。
    init(state: LiveTelemetryState) {
        banner = LiveTelemetryStatusBanner(state: state)
        showsSamples = state.isConnectionActive && !state.samples.isEmpty
        showsRetry = state.phase == .failed && state.endpoint != nil && state.vehicle != nil
        respondingPIDCount = state.isConnectionActive && state.supportedPIDCount > 0 ? state.supportedPIDCount : nil
        groups = LiveTelemetrySampleGroups(samples: state.samples)
        isEmpty = banner == nil && !showsSamples && !showsRetry
    }
}

/// Live Activityに並べる計測項目の種類です。SwiftUIに依存しない純粋型で、アプリとWidget Extensionの両方に属します。
nonisolated enum RecordingSessionLiveActivityMetricKind: CaseIterable, Hashable {
    /// 車速(km/h)です。
    case vehicleSpeed
    /// エンジン回転数(rpm)です。
    case engineSpeed
    /// スロットル開度(%)です。
    case throttlePosition

    /// 項目の見出しのローカライズキーです。
    var labelKey: String {
        switch self {
        case .vehicleSpeed: "live_activity.label.vehicle_speed"
        case .engineSpeed: "live_activity.label.engine_speed"
        case .throttlePosition: "live_activity.label.throttle_position"
        }
    }

    /// 項目の単位のローカライズキーです。
    var unitKey: String {
        switch self {
        case .vehicleSpeed: "live_activity.unit.vehicle_speed"
        case .engineSpeed: "live_activity.unit.engine_speed"
        case .throttlePosition: "live_activity.unit.throttle_position"
        }
    }

    /// 表示内容からこの項目の計測値を取り出します。
    ///
    /// 責務: 項目の種類を `ContentState` の対応する計測値へ結び付けます。
    /// - Parameter state: Live Activityの表示内容。
    /// - Returns: この項目の計測値。
    func metric(in state: RecordingSessionActivityAttributes.ContentState) -> RecordingSessionActivityAttributes.Metric {
        switch self {
        case .vehicleSpeed: state.vehicleSpeed
        case .engineSpeed: state.engineSpeed
        case .throttlePosition: state.throttlePosition
        }
    }
}

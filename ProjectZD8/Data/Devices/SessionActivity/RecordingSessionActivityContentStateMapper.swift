#if os(iOS)
/// Applicationの表示内容 `RecordingSessionActivityContent` を、Live Activityの `ContentState` へ写します。
///
/// `RecordingSessionActivityAttributes` はWidget Extensionと共有する自己完結の型のため、Application型への変換はこの型が担います。
nonisolated struct RecordingSessionActivityContentStateMapper: Sendable {
    /// 変換器を生成します。
    ///
    /// 責務: 状態を持たない変換器を作ります。
    init() {}

    /// 表示内容を `ContentState` へ写します。
    ///
    /// 責務: 項目ごとに同じ意味のケース・値へ変換します。
    /// - Parameter content: Applicationが作った表示内容。
    /// - Returns: Live Activityへ渡す表示内容。
    func contentState(from content: RecordingSessionActivityContent) -> RecordingSessionActivityAttributes.ContentState {
        RecordingSessionActivityAttributes.ContentState(
            vehicle: vehicleLabel(from: content.vehicle),
            statusKey: content.statusKey,
            statusTone: content.statusTone == .warning ? .warning : .normal,
            vehicleSpeed: metric(from: content.vehicleSpeed),
            engineSpeed: metric(from: content.engineSpeed),
            throttlePosition: metric(from: content.throttlePosition),
            receivedResponseCount: content.receivedResponseCount,
            startedAt: content.startedAt,
            vehiclePhotoFileName: content.vehiclePhotoFileName
        )
    }

    /// 車両名欄を写します。
    ///
    /// 責務: 名称あり/未登録を同じケースへ変換します。
    /// - Parameter label: Applicationの車両名欄。
    /// - Returns: Live Activityの車両名欄。
    private func vehicleLabel(
        from label: RecordingSessionActivityVehicleLabel
    ) -> RecordingSessionActivityAttributes.VehicleLabel {
        switch label {
        case let .named(name): .named(name)
        case .unregistered: .unregistered
        }
    }

    /// 計測値を写します。
    ///
    /// 責務: 値あり/未取得を同じケースへ変換します。
    /// - Parameter metric: Applicationの計測値。
    /// - Returns: Live Activityの計測値。
    private func metric(from metric: RecordingSessionActivityMetric) -> RecordingSessionActivityAttributes.Metric {
        switch metric {
        case let .value(value): .value(value)
        case .unavailable: .unavailable
        }
    }
}
#endif

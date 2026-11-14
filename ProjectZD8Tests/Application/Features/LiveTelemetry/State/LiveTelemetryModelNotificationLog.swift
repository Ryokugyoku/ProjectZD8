@testable import ProjectZD8

/// LiveTelemetryModel が Logging へ通知した終了原因と累積距離を記録します。
@MainActor
final class LiveTelemetryModelNotificationLog {
    /// 通知された終了原因です。通知順に並びます。
    private(set) var endReasons: [ConnectionSessionEndReason] = []
    /// 通知された累積距離です。通知順に並びます。
    private(set) var distances: [ConnectionSessionDistanceObservation] = []

    /// 空の通知履歴を生成します。
    ///
    /// 責務: 終了原因と累積距離の記録先を空状態で構築します。
    init() {}

    /// 終了原因を記録します。
    ///
    /// 責務: 1件の終了原因を履歴へ追加します。
    /// - Parameter reason: 通知された終了原因。
    func recordEnd(_ reason: ConnectionSessionEndReason) {
        endReasons.append(reason)
    }

    /// 累積距離を記録します。
    ///
    /// 責務: 1件の累積距離を履歴へ追加します。
    /// - Parameter observation: 通知された累積距離。
    func recordDistance(_ observation: ConnectionSessionDistanceObservation) {
        distances.append(observation)
    }
}

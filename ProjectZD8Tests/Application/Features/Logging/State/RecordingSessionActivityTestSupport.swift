import Foundation
@testable import ProjectZD8

/// 記録中表示のテストが共有する取得状態・観測の生成部品です。
enum RecordingSessionActivityTestSupport {
    /// 指定のPIDと値を持つ観測を生成します。
    ///
    /// 責務: 要求と値だけが異なる観測を1件返します。
    /// - Parameters:
    ///   - request: 観測のService/PID。
    ///   - value: 観測値。
    /// - Returns: 観測。
    static func sample(_ request: OBDPIDRequest, value: Double) -> OBDPIDSample {
        OBDPIDSample(
            request: request, nameKey: "test.pid", value: value, unit: "u",
            observedAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// 指定の段階と一時停止状態を持つ取得状態を生成します。
    ///
    /// 責務: 段階・一時停止・失敗キー・観測・受信件数だけを差し替えた状態を返します。
    /// - Parameters:
    ///   - phase: 取得段階。
    ///   - pause: 一時停止の取得ループ段階。無ければ `nil`。
    ///   - failureKey: 失敗キー。
    ///   - samples: 観測一覧。
    ///   - receivedCount: 受信件数。
    /// - Returns: 取得状態。
    @MainActor
    static func state(
        _ phase: LiveTelemetryState.Phase,
        pause: LiveTelemetryAcquisitionPhase? = nil,
        failureKey: String? = nil,
        samples: [OBDPIDSample] = [],
        receivedCount: Int = 0
    ) -> LiveTelemetryState {
        var state = LiveTelemetryState()
        state.phase = phase
        state.pauseStatus = pause.flatMap { LiveTelemetryPauseStatus($0) }
        state.failureKey = failureKey
        state.samples = samples
        state.receivedResponseCount = receivedCount
        return state
    }
}

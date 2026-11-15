@testable import ProjectZD8

/// 記録の開始・停止を依頼する境界の spy です。
@MainActor
final class AdapterLinkRecordingControlSpy: AdapterLinkRecordingControlPort {
    /// 渡された記録開始要求です(要求順)。
    private(set) var startRequests: [AdapterLinkRecordingStartRequest] = []

    /// 停止要求の回数です。
    private(set) var stopRequestCount = 0

    /// 停止要求に添えられた理由です(要求順)。
    private(set) var stopReasons: [AdapterLinkRecordingStopReason] = []

    /// 伝えられた記録中のリンク可用性の変化です(通知順)。
    private(set) var linkAvailabilityChanges: [Bool] = []

    /// 記録開始要求を記録します。
    ///
    /// 責務: 渡された要求を要求順に記録します。
    /// - Parameter request: 記録開始要求。
    func requestRecordingStart(_ request: AdapterLinkRecordingStartRequest) {
        startRequests.append(request)
    }

    /// 停止要求を記録します。
    ///
    /// 責務: 停止要求の回数を数え、理由を要求順に記録します。
    /// - Parameter reason: 停止の理由。
    func requestRecordingStop(reason: AdapterLinkRecordingStopReason) {
        stopRequestCount += 1
        stopReasons.append(reason)
    }

    /// 記録中のリンク可用性の変化を記録します。
    ///
    /// 責務: 渡された変化を通知順に記録します。
    /// - Parameter isAvailable: リンクが `ready` へ戻ったら `true`、`ready` でなくなったら `false`。
    func recordingLinkAvailabilityDidChange(isAvailable: Bool) {
        linkAvailabilityChanges.append(isAvailable)
    }
}

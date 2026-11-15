@testable import ProjectZD8

/// 記録の開始・停止を依頼する境界の spy です。
@MainActor
final class AdapterLinkRecordingControlSpy: AdapterLinkRecordingControlPort {
    /// 渡された記録開始要求です(要求順)。
    private(set) var startRequests: [AdapterLinkRecordingStartRequest] = []

    /// 停止要求の回数です。
    private(set) var stopRequestCount = 0

    /// 記録開始要求を記録します。
    ///
    /// 責務: 渡された要求を要求順に記録します。
    /// - Parameter request: 記録開始要求。
    func requestRecordingStart(_ request: AdapterLinkRecordingStartRequest) {
        startRequests.append(request)
    }

    /// 停止要求を記録します。
    ///
    /// 責務: 停止要求の回数を数えます。
    func requestRecordingStop() {
        stopRequestCount += 1
    }
}

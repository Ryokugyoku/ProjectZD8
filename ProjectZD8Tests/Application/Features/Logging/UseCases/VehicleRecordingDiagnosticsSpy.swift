@testable import ProjectZD8

/// 記録の調停役が診断ポートへ伝えた開始拒否と照合失敗を順に記録する spy です。
@MainActor
final class VehicleRecordingDiagnosticsSpy: VehicleRecordingDiagnosticsPort {
    /// 伝えられた開始拒否の理由です。
    private(set) var declineReasons: [VehicleRecordingStartDeclineReason] = []

    /// 伝えられた照合失敗のエラーです。
    private(set) var lookupFailures: [any Error] = []

    /// 責務: 開始拒否の理由を記録します。
    /// - Parameter reason: 開始を断った理由。
    func recordingStartDeclined(_ reason: VehicleRecordingStartDeclineReason) {
        declineReasons.append(reason)
    }

    /// 責務: 照合失敗のエラーを記録します。
    /// - Parameter error: 照合で発生したエラー。
    func vehicleLookupFailed(_ error: any Error) {
        lookupFailures.append(error)
    }
}

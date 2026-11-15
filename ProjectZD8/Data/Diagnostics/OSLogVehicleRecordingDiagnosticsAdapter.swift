import Foundation
import OSLog

/// 記録の調停役の診断記録を統合ログ(`Logger`)へ出力します。
@MainActor
final class OSLogVehicleRecordingDiagnosticsAdapter: VehicleRecordingDiagnosticsPort {
    /// 出力先のロガーです。
    private let logger = Logger(subsystem: DiagnosticsLogSubsystem.identifier, category: "VehicleRecording")

    /// 記録開始要求を断ったことを出力します。
    ///
    /// 責務: 想定外の重複要求は fault、別セッション進行中による拒否は info として出力します。
    /// - Parameter reason: 断った理由。
    func recordingStartDeclined(_ reason: VehicleRecordingStartDeclineReason) {
        switch reason {
        case let .coordinatorBusy(phase):
            logger.fault("Recording start requested while phase=\(String(describing: phase), privacy: .public)")
        case .anotherSessionActive:
            logger.info("Recording start declined because another session is active")
        }
    }

    /// 登録済み車両の照合に失敗したことを出力します。
    ///
    /// 責務: 照合エラーを error として出力します。
    /// - Parameter error: 照合で発生したエラー。
    func vehicleLookupFailed(_ error: any Error) {
        logger.error("Registered vehicle lookup failed: \(String(describing: error), privacy: .public)")
    }
}

import Foundation
import OSLog

/// 応答駆動の取得ループの診断記録を統合ログ(`Logger`、category `Acquisition`)へ出力します。
///
/// 文言は `LiveTelemetryAcquisitionDiagnosticsMessageFormatter` が決め、この型は出力の重要度だけを決めます。
/// 開始・取得中・停止は info、回復中・一時停止は notice、猶予切れ・記録失敗は error です。
/// 文言は識別子や計測値を含まないため public で出します。
@MainActor
final class OSLogLiveTelemetryAcquisitionDiagnosticsAdapter: LiveTelemetryAcquisitionDiagnosticsPort {
    /// 出力先のロガーです。
    private let logger = Logger(subsystem: DiagnosticsLogSubsystem.identifier, category: "Acquisition")
    /// 文言の整形器です。
    private let formatter = LiveTelemetryAcquisitionDiagnosticsMessageFormatter()

    /// 取得を始めたことを出力します。
    ///
    /// 責務: 取得開始を info として出力します。
    func acquisitionStarted() {
        let message = formatter.started()
        logger.info("\(message, privacy: .public)")
    }

    /// 段階が変わったことを出力します。
    ///
    /// 責務: 取得中を info、回復中と一時停止を notice として出力します。
    /// - Parameter phase: 変化後の段階。
    func acquisitionPhaseChanged(_ phase: LiveTelemetryAcquisitionPhase) {
        let message = formatter.phaseChanged(phase)
        switch phase {
        case .acquiring: logger.info("\(message, privacy: .public)")
        case .recovering, .paused: logger.notice("\(message, privacy: .public)")
        }
    }

    /// 停止で終わったことを出力します。
    ///
    /// 責務: 停止による終了を info として出力します。
    func acquisitionStopped() {
        let message = formatter.stopped()
        logger.info("\(message, privacy: .public)")
    }

    /// 猶予切れで終わったことを出力します。
    ///
    /// 責務: 猶予切れによる終了を error として出力します。
    /// - Parameter cause: 取得が途切れた原因。
    func acquisitionGracePeriodExpired(cause: LiveTelemetryInterruptionCause) {
        let message = formatter.gracePeriodExpired(cause: cause)
        logger.error("\(message, privacy: .public)")
    }

    /// 記録失敗で終わったことを出力します。
    ///
    /// 責務: 記録失敗による終了を error として出力します。
    func acquisitionRecordingFailed() {
        let message = formatter.recordingFailed()
        logger.error("\(message, privacy: .public)")
    }
}

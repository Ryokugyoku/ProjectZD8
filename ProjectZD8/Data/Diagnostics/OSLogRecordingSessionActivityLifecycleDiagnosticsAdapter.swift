import Foundation
import OSLog

/// 記録中の常時表示(Live Activity)の状態遷移の診断記録を統合ログ(`Logger`、category `LiveActivity`)へ出力します。
///
/// 文言は `RecordingSessionActivityLifecycleDiagnosticsMessageFormatter` が決め、この型は出力の重要度だけを決めます。
/// システムによる終了と断った停止要求は notice、それ以外は info です。文言は識別子や計測値を含まないため public で出します。
@MainActor
final class OSLogRecordingSessionActivityLifecycleDiagnosticsAdapter: RecordingSessionActivityLifecycleDiagnosticsPort {
    /// 出力先のロガーです。
    private let logger = Logger(subsystem: DiagnosticsLogSubsystem.identifier, category: "LiveActivity")
    /// 文言の整形器です。
    private let formatter = RecordingSessionActivityLifecycleDiagnosticsMessageFormatter()

    /// 表示を開始できたことを出力します。
    ///
    /// 責務: 表示開始を info として出力します。
    func activityStarted() {
        let message = formatter.started()
        logger.info("\(message, privacy: .public)")
    }

    /// アプリが表示を終了したことを出力します。
    ///
    /// 責務: アプリによる表示終了を info として出力します。
    func activityEnded() {
        let message = formatter.ended()
        logger.info("\(message, privacy: .public)")
    }

    /// システムまたはユーザーに表示を閉じられたことを出力します。
    ///
    /// 責務: アプリ以外による表示終了を notice として出力します。
    func activityClosedBySystem() {
        let message = formatter.closedBySystem()
        logger.notice("\(message, privacy: .public)")
    }

    /// [切断]の要求を受け付けたことを出力します。
    ///
    /// 責務: 受け付けた停止要求を info として出力します。
    func stopRequestAccepted() {
        let message = formatter.stopRequestAccepted()
        logger.info("\(message, privacy: .public)")
    }

    /// [切断]の要求を断ったことを出力します。
    ///
    /// 責務: 断った停止要求を notice として出力します。
    func stopRequestDeclined() {
        let message = formatter.stopRequestDeclined()
        logger.notice("\(message, privacy: .public)")
    }
}

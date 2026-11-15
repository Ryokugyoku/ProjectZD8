import Foundation
import OSLog

/// 記録中表示の診断記録を統合ログ(`Logger`)へ出力します。
@MainActor
final class OSLogRecordingSessionActivityDiagnosticsAdapter: RecordingSessionActivityDiagnosticsPort {
    /// 出力先のロガーです。
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProjectZD8", category: "RecordingSessionActivity")

    /// 記録中表示の操作に失敗したことを出力します。
    ///
    /// 責務: 操作の種類とエラーを error として出力します。
    /// - Parameters:
    ///   - operation: 失敗した操作。
    ///   - error: 発生したエラー。
    func operationFailed(_ operation: RecordingSessionActivityOperation, error: any Error) {
        logger.error(
            "Session activity \(String(describing: operation), privacy: .public) failed: \(String(describing: error), privacy: .public)"
        )
    }
}

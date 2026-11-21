import Foundation
import OSLog

/// 位置記録の保存失敗を統合ログ(`Logger`)へ出力します。
///
/// 位置の値(緯度経度)は出力しません。出すのはセッション識別子・状態の種類・エラーの説明だけです。
/// 記録はメインスレッド外から呼ばれるため、状態を持たない `nonisolated` な型にしています。
nonisolated final class OSLogSessionLocationRecordingDiagnosticsAdapter: SessionLocationRecordingDiagnosticsPort {
    /// 出力先のロガーです。
    private let logger = Logger(subsystem: DiagnosticsLogSubsystem.identifier, category: "SessionLocationRecording")

    /// 状態を持たない出力先を生成します。
    ///
    /// 責務: 統合ログへの出力先を構築します。
    init() {}

    /// 位置の保存失敗を出力します。
    ///
    /// 責務: セッション識別子とエラーを error として出力し、位置の値は出しません。
    /// - Parameters:
    ///   - sessionID: 保存先の接続セッション。
    ///   - error: 保存の失敗。
    func sampleStorageFailed(sessionID: ConnectionSessionID, error: any Error) {
        logger.error(
            "Location sample storage failed for session \(sessionID.rawValue.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
        )
    }

    /// 状態変化の保存失敗を出力します。
    ///
    /// 責務: 状態の種類・セッション識別子・エラーを error として出力します。
    /// - Parameters:
    ///   - kind: 保存できなかった状態の種類。
    ///   - sessionID: 保存先の接続セッション。
    ///   - error: 保存の失敗。
    func eventStorageFailed(
        _ kind: ConnectionSessionLocationEventKind,
        sessionID: ConnectionSessionID,
        error: any Error
    ) {
        let session = sessionID.rawValue.uuidString
        let reason = String(describing: error)
        logger.error(
            "Location event \(kind.rawValue, privacy: .public) storage failed for session \(session, privacy: .public): \(reason, privacy: .public)"
        )
    }
}

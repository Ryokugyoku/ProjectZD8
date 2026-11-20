import Foundation
import OSLog

/// 走行ルート(位置の軌跡)の即時アップロードの結果を統合ログ(`Logger`)へ出力します。
///
/// 出すのは件数とエラーの domain・code だけで、座標・セッション識別子・アカウント識別子は出しません。
/// 状態を持たないため `nonisolated` な型にしています。
nonisolated final class OSLogConnectionSessionLocationTrackSyncDiagnosticsAdapter: ConnectionSessionLocationTrackSyncDiagnosticsPort {
    /// 出力先のロガーです。
    private let logger = Logger(subsystem: DiagnosticsLogSubsystem.identifier, category: "LocationTrackSync")

    /// 状態を持たない出力先を生成します。
    ///
    /// 責務: 統合ログへの出力先を構築します。
    init() {}

    /// 即時アップロードの失敗を出力します。
    ///
    /// 責務: エラーの domain と code を error として出力します。
    /// - Parameters:
    ///   - errorDomain: 失敗したエラーの `domain`。
    ///   - errorCode: 失敗したエラーの `code`。
    func immediateUploadFailed(errorDomain: String, errorCode: Int) {
        logger.error(
            "Immediate location track upload failed: \(errorDomain, privacy: .public) \(errorCode, privacy: .public)"
        )
    }

    /// 即時アップロードの成功を出力します。
    ///
    /// 責務: アップロード件数を info として出力します。
    /// - Parameter uploadedCount: アップロードしたセッションの件数。
    func immediateUploadSucceeded(uploadedCount: Int) {
        logger.info("Immediate location track upload succeeded: \(uploadedCount, privacy: .public) session(s)")
    }
}

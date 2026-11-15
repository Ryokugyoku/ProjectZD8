import Foundation
import OSLog

/// 記録セッション終了後の後処理の診断記録を統合ログ(`Logger`)へ出力します。
///
/// 文言は `PostSessionProcessingDiagnosticsMessageFormatter` が決め、この型は出力の重要度だけを決めます。
/// 失敗は error、持ち越しと中断は notice、それ以外は info です。文言はアカウント識別子等を含まないため public で出します。
@MainActor
final class OSLogPostSessionProcessingDiagnosticsAdapter: PostSessionProcessingDiagnosticsPort {
    /// 出力先のロガーです。
    private let logger = Logger(subsystem: DiagnosticsLogSubsystem.identifier, category: "PostSessionProcessing")
    /// 文言の整形器です。
    private let formatter = PostSessionProcessingDiagnosticsMessageFormatter()

    /// 予約に成功したことを出力します。
    ///
    /// 責務: 予約成功を info として出力します。
    func scheduled() {
        info(formatter.scheduled())
    }

    /// 予約に失敗したことを出力します。
    ///
    /// 責務: 予約失敗を error として出力します。
    /// - Parameters:
    ///   - errorDomain: 失敗したエラーの `domain`。
    ///   - errorCode: 失敗したエラーの `code`。
    func scheduleFailed(errorDomain: String, errorCode: Int) {
        error(formatter.scheduleFailed(errorDomain: errorDomain, errorCode: errorCode))
    }

    /// 実行を始めたことを出力します。
    ///
    /// 責務: 実行開始を info として出力します。
    func started() {
        info(formatter.started())
    }

    /// 記録中のため持ち越したことを出力します。
    ///
    /// 責務: 記録中による持ち越しを notice として出力します。
    func deferredForActiveRecording() {
        notice(formatter.deferredForActiveRecording())
    }

    /// アカウント未解決のため持ち越したことを出力します。
    ///
    /// 責務: アカウント未解決による持ち越しを notice として出力します。
    func deferredForUnavailableAccount() {
        notice(formatter.deferredForUnavailableAccount())
    }

    /// 自動アップロードがオフのためアップロードを省いたことを出力します。
    ///
    /// 責務: 設定によるアップロード省略を info として出力します。
    func uploadSkippedForAutomaticUploadOff() {
        info(formatter.uploadSkippedForAutomaticUploadOff())
    }

    /// ステップが成功したことを出力します。
    ///
    /// 責務: ステップ成功を info として出力します。
    /// - Parameter step: 成功したステップ。
    func stepSucceeded(_ step: PostSessionProcessingStep) {
        info(formatter.stepSucceeded(step))
    }

    /// ステップが失敗したことを出力します。
    ///
    /// 責務: ステップ失敗を error として出力します。
    /// - Parameters:
    ///   - step: 失敗したステップ。
    ///   - errorDomain: 失敗したエラーの `domain`。
    ///   - errorCode: 失敗したエラーの `code`。
    func stepFailed(_ step: PostSessionProcessingStep, errorDomain: String, errorCode: Int) {
        error(formatter.stepFailed(step, errorDomain: errorDomain, errorCode: errorCode))
    }

    /// 期限切れで中断したことを出力します。
    ///
    /// 責務: 期限切れによる中断を notice として出力します。
    func interruptedByExpiration() {
        notice(formatter.interruptedByExpiration())
    }

    /// 実行を終えたことを出力します。
    ///
    /// 責務: 実行結果を info として出力します。
    /// - Parameter outcome: 実行結果。
    func finished(_ outcome: PostSessionProcessingOutcome) {
        info(formatter.finished(outcome))
    }

    /// 文言を info として出力します。
    ///
    /// 責務: 1件の文言を info の重要度でロガーへ渡します。
    /// - Parameter message: 出力する文言。
    private func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    /// 文言を notice として出力します。
    ///
    /// 責務: 1件の文言を notice の重要度でロガーへ渡します。
    /// - Parameter message: 出力する文言。
    private func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    /// 文言を error として出力します。
    ///
    /// 責務: 1件の文言を error の重要度でロガーへ渡します。
    /// - Parameter message: 出力する文言。
    private func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

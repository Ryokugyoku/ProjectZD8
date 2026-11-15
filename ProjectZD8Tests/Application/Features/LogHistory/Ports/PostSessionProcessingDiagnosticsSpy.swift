@testable import ProjectZD8

/// 後処理の診断ポートへ伝えられた出来事を順に記録する spy です。
@MainActor
final class PostSessionProcessingDiagnosticsSpy: PostSessionProcessingDiagnosticsPort {
    /// 診断ポートへ伝えられた1件の出来事です。
    enum Event: Equatable {
        /// 予約した。
        case scheduled
        /// 予約に失敗した。
        case scheduleFailed(domain: String, code: Int)
        /// 実行を始めた。
        case started
        /// 記録中のため持ち越した。
        case deferredForActiveRecording
        /// アカウント未解決のため持ち越した。
        case deferredForUnavailableAccount
        /// 設定オフのためアップロードを省いた。
        case uploadSkippedForAutomaticUploadOff
        /// ステップが成功した。
        case stepSucceeded(PostSessionProcessingStep)
        /// ステップが失敗した。
        case stepFailed(PostSessionProcessingStep, domain: String, code: Int)
        /// 期限切れで中断した。
        case interruptedByExpiration
        /// 実行を終えた。
        case finished(PostSessionProcessingOutcome)

        /// 予約に関する出来事かどうかです。
        var isScheduling: Bool {
            switch self {
            case .scheduled, .scheduleFailed: true
            default: false
            }
        }
    }

    /// 伝えられた出来事です。
    private(set) var events: [Event] = []

    /// 予約に関する出来事を除いた、実行の経過の出来事です。
    var processingEvents: [Event] {
        events.filter { !$0.isScheduling }
    }

    /// 予約に関する出来事だけです。
    var schedulingEvents: [Event] {
        events.filter(\.isScheduling)
    }

    /// 責務: 予約成功を記録します。
    func scheduled() {
        events.append(.scheduled)
    }

    /// 責務: 予約失敗とエラー分類を記録します。
    /// - Parameters:
    ///   - errorDomain: エラーの `domain`。
    ///   - errorCode: エラーの `code`。
    func scheduleFailed(errorDomain: String, errorCode: Int) {
        events.append(.scheduleFailed(domain: errorDomain, code: errorCode))
    }

    /// 責務: 実行開始を記録します。
    func started() {
        events.append(.started)
    }

    /// 責務: 記録中による持ち越しを記録します。
    func deferredForActiveRecording() {
        events.append(.deferredForActiveRecording)
    }

    /// 責務: アカウント未解決による持ち越しを記録します。
    func deferredForUnavailableAccount() {
        events.append(.deferredForUnavailableAccount)
    }

    /// 責務: 設定オフによるアップロード省略を記録します。
    func uploadSkippedForAutomaticUploadOff() {
        events.append(.uploadSkippedForAutomaticUploadOff)
    }

    /// 責務: ステップ成功を記録します。
    /// - Parameter step: 成功したステップ。
    func stepSucceeded(_ step: PostSessionProcessingStep) {
        events.append(.stepSucceeded(step))
    }

    /// 責務: ステップ失敗とエラー分類を記録します。
    /// - Parameters:
    ///   - step: 失敗したステップ。
    ///   - errorDomain: エラーの `domain`。
    ///   - errorCode: エラーの `code`。
    func stepFailed(_ step: PostSessionProcessingStep, errorDomain: String, errorCode: Int) {
        events.append(.stepFailed(step, domain: errorDomain, code: errorCode))
    }

    /// 責務: 期限切れによる中断を記録します。
    func interruptedByExpiration() {
        events.append(.interruptedByExpiration)
    }

    /// 責務: 実行結果を記録します。
    /// - Parameter outcome: 実行結果。
    func finished(_ outcome: PostSessionProcessingOutcome) {
        events.append(.finished(outcome))
    }
}

import Foundation
@testable import ProjectZD8

/// 1件の非同期書き込みを別タスクで開始し、終わった結果を記録します。
///
/// テストは結果を `BLEBoundedWaiter` で上限付きで待つため、書き込みが戻らない実装でもテストは止まりません。
@MainActor
final class BLEWriteAttemptRecorder {
    /// 書き込みの結果です。
    enum Outcome: Equatable {
        /// 成功しました。
        case succeeded
        /// `AdapterLinkWriteError` で失敗しました。
        case failed(AdapterLinkWriteError)
        /// 想定外のエラーで失敗しました。
        case failedUnexpectedly(String)
    }

    /// 終わった結果です。未完了なら `nil`。
    private(set) var outcome: Outcome?
    /// 書き込みを実行するタスクです。
    private var task: Task<Void, Never>?

    /// 書き込みを開始します。
    ///
    /// 責務: 指定処理を別タスクで実行し、結果を `outcome` へ記録します。
    /// - Parameter operation: 実行する書き込み。
    init(_ operation: @escaping @MainActor () async throws -> Void) {
        task = Task { [weak self] in
            let result: Outcome
            do {
                try await operation()
                result = .succeeded
            } catch let error as AdapterLinkWriteError {
                result = .failed(error)
            } catch {
                result = .failedUnexpectedly(String(describing: error))
            }
            self?.outcome = result
        }
    }

    /// 完了したかどうかです。
    var isFinished: Bool { outcome != nil }
}

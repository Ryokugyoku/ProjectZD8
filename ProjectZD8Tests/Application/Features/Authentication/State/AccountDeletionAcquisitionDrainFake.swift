import Foundation
@testable import ProjectZD8

/// 記録の終了待ちを保留・失敗できるFakeです。
@MainActor
final class AccountDeletionAcquisitionDrainFake: AccountDeletionAcquisitionDrainPort {
    /// 投げるエラーです。`nil` なら成功します。
    var error: Error?

    /// `true` の間は `release()` まで保留します。
    var holds = false

    /// 呼び出し回数です。
    private(set) var callCount = 0

    /// 保留中の継続です。
    private var continuation: CheckedContinuation<Void, Never>?

    /// 保留に入っているかどうかです。
    var isWaiting: Bool { continuation != nil }

    /// 保留を解いて以後は保留しません。
    ///
    /// 責務: テスト終了時に保留中のタスクを取り残さないようにします。
    func release() {
        holds = false
        continuation?.resume()
        continuation = nil
    }

    /// 呼び出しを記録し、指定どおりに保留・失敗・成功します。
    ///
    /// 責務: 終了待ちの結果をテストが制御できるようにします。
    func endAcquisitionAndWaitUntilSaved() async throws {
        callCount += 1
        if holds {
            await withCheckedContinuation { continuation = $0 }
        }
        if let error { throw error }
    }
}

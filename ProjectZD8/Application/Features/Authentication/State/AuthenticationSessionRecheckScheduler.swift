/// サインイン確認の再確認を、判定 `AuthenticationSessionRecheckPolicy` の待ち時間と上限で順に実行します。
///
/// 待機は注入した処理で行い、実時間に依存しません。再確認の中身(照会と状態への反映)は呼び出し元が渡します。
/// 取り消し(`cancel()`)の後に戻った照会の結果は、呼び出し元が `Task.isCancelled` で捨てます。
@MainActor
final class AuthenticationSessionRecheckScheduler {
    /// 指定時間だけ待つ処理です。取り消し時は throw するか戻ります。テストは実時間を待たない実装を注入します。
    typealias Sleep = @Sendable (Duration) async throws -> Void

    /// 1回の再確認の結果です。
    enum Outcome: Equatable {
        /// 確認できた(サインイン済み、または本当に未サインイン)ので再確認をやめます。
        case resolved
        /// まだ確認できないので、次の待ち時間の後に再確認します。
        case unresolved
    }

    /// 待ち時間と上限の判定です。
    private let policy: AuthenticationSessionRecheckPolicy
    /// 待機に使う処理です。
    private let sleep: Sleep
    /// 実行中の再確認の列です。
    private var task: Task<Void, Never>?
    /// 列を始めるたび・取り消すたびに進む世代です。古い列の終わりで新しい列を外さないために使います。
    private var generation = 0

    /// 判定と待機手段を固定して生成します。
    ///
    /// 責務: 再確認の待ち時間・上限と、待機の処理を保持します。
    /// - Parameters:
    ///   - policy: 待ち時間と上限の判定。
    ///   - sleep: 指定時間待つ処理。
    init(policy: AuthenticationSessionRecheckPolicy, sleep: @escaping Sleep) {
        self.policy = policy
        self.sleep = sleep
    }

    /// 再確認の列が動いているかどうかです。
    var isRunning: Bool { task != nil }

    /// 回数を0から取り直して再確認の列を始めます。動いている列は取り消します。
    ///
    /// 責務: `immediately` なら待たずに1回再確認し(回数に数えない)、確認できなければ判定の待ち時間ごとに上限まで再確認します。
    /// - Parameters:
    ///   - immediately: 最初に待たずに1回再確認するかどうか(前面復帰で使います)。
    ///   - recheck: 1回の再確認。照会し、結果を状態へ反映して `Outcome` を返します。
    func start(immediately: Bool, recheck: @escaping @MainActor () async -> Outcome) {
        cancel()
        let policy = policy
        let sleep = sleep
        let started = generation
        task = Task { [weak self] in
            defer { self?.finish(started) }
            if immediately {
                guard await recheck() == .unresolved, !Task.isCancelled else { return }
            }
            var attempt = 0
            while let delay = policy.delay(beforeAttempt: attempt) {
                do { try await sleep(delay) } catch { return }
                guard !Task.isCancelled else { return }
                attempt += 1
                guard await recheck() == .unresolved, !Task.isCancelled else { return }
            }
        }
    }

    /// 再確認の列を取り消します。
    ///
    /// 責務: 待機中・照会中の列を取り消し、以後の再確認を行わないようにします。
    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
    }

    /// 列が自然に終わったことを記録します。
    ///
    /// 責務: 終わった列が現在の世代の列である時だけ、動いている列を外します。
    /// - Parameter finished: 終わった列を始めた時の世代。
    private func finish(_ finished: Int) {
        guard finished == generation else { return }
        task = nil
    }
}

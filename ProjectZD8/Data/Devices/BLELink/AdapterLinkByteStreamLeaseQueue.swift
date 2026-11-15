import Foundation

/// 常駐リンク上のバイトストリームの占有権を、到着順に1利用者ずつ渡す待ち行列です。
///
/// 占有中に要求した利用者は上限時間まで待ち、上限を超えると `AdapterLinkByteStreamError.leaseUnavailable` で失敗します。
@MainActor
final class AdapterLinkByteStreamLeaseQueue {
    /// 占有権を待っている1利用者です。
    private struct Waiter {
        /// 渡す占有権の通し番号です。
        let id: UInt64
        /// 占有権の受け渡し先です。
        let continuation: CheckedContinuation<AdapterLinkByteStreamLease, any Error>
        /// 待機上限の監視タスクです。
        let timeoutTask: Task<Void, Never>
    }

    /// 現在の占有権です。誰も占有していなければ `nil`。
    private(set) var holder: AdapterLinkByteStreamLease?
    /// 占有者が替わった(取得・解放)ときに呼ぶ処理です。
    var holderDidChange: (@MainActor () -> Void)?

    /// 占有権を待つ上限です。
    private let timeout: Duration
    /// 待機に使う処理です。テストは実時間を待たない実装を渡します。
    private let sleep: @Sendable (Duration) async throws -> Void
    /// 到着順の待機者です。
    private var waiters: [Waiter] = []
    /// 最後に払い出した通し番号です。
    private var lastIssuedID: UInt64 = 0

    /// 待機上限と待機処理を固定して生成します。
    ///
    /// 責務: 占有権の待ち行列を空の状態で用意します。
    /// - Parameters:
    ///   - timeout: 占有権を待つ上限。
    ///   - sleep: 待機に使う処理。キャンセル時は throw すること。
    init(timeout: Duration, sleep: @escaping @Sendable (Duration) async throws -> Void) {
        self.timeout = timeout
        self.sleep = sleep
    }

    /// 占有権を取得します。
    ///
    /// 責務: 空いていれば即座に、占有中なら到着順で解放を待って1件の占有権を渡します。
    /// - Returns: 取得した占有権。
    /// - Throws: 上限までに得られない場合は `AdapterLinkByteStreamError.leaseUnavailable`、キャンセル時は `CancellationError`。
    func acquire() async throws -> AdapterLinkByteStreamLease {
        let id = issueID()
        if holder == nil, waiters.isEmpty {
            return grant(id)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enqueue(id: id, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.failWaiter(id, with: CancellationError())
            }
        }
    }

    /// 占有権を解放します。
    ///
    /// 責務: 現在の占有者が渡した占有権だけを解放し、待機者がいれば先頭へ渡します。
    /// - Parameter lease: 解放する占有権。現在の占有者でなければ何もしません。
    func release(_ lease: AdapterLinkByteStreamLease) {
        guard holder == lease else { return }
        holder = nil
        holderDidChange?()
        guard !waiters.isEmpty else { return }
        let next = waiters.removeFirst()
        next.timeoutTask.cancel()
        next.continuation.resume(returning: grant(next.id))
    }

    /// 次の通し番号を払い出します。
    ///
    /// 責務: 解放済みの占有権と衝突しない一意な番号を返します。
    /// - Returns: 新しい通し番号。
    private func issueID() -> UInt64 {
        lastIssuedID &+= 1
        return lastIssuedID
    }

    /// 占有権を渡します。
    ///
    /// 責務: 指定番号を現在の占有者にして通知します。
    /// - Parameter id: 渡す占有権の通し番号。
    /// - Returns: 渡した占有権。
    private func grant(_ id: UInt64) -> AdapterLinkByteStreamLease {
        let lease = AdapterLinkByteStreamLease(id: id)
        holder = lease
        holderDidChange?()
        return lease
    }

    /// 待機者を行列の末尾へ加えます。
    ///
    /// 責務: キャンセル済みなら即座に失敗させ、そうでなければ待機上限の監視付きで登録します。
    /// - Parameters:
    ///   - id: 渡す占有権の通し番号。
    ///   - continuation: 占有権の受け渡し先。
    private func enqueue(id: UInt64, continuation: CheckedContinuation<AdapterLinkByteStreamLease, any Error>) {
        guard !Task.isCancelled else {
            continuation.resume(throwing: CancellationError())
            return
        }
        let timeout = timeout
        let sleep = sleep
        let timeoutTask = Task { @MainActor [weak self] in
            do { try await sleep(timeout) } catch { return }
            self?.failWaiter(id, with: AdapterLinkByteStreamError.leaseUnavailable)
        }
        waiters.append(Waiter(id: id, continuation: continuation, timeoutTask: timeoutTask))
    }

    /// 待機者を失敗させて行列から取り除きます。
    ///
    /// 責務: 指定番号の待機者がまだ待っている場合だけ、指定エラーで終わらせます。
    /// - Parameters:
    ///   - id: 失敗させる待機者の通し番号。
    ///   - error: 待機者へ渡すエラー。
    private func failWaiter(_ id: UInt64, with error: any Error) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.timeoutTask.cancel()
        waiter.continuation.resume(throwing: error)
    }
}

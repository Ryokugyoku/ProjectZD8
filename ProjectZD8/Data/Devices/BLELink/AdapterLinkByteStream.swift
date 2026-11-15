import Foundation

/// 常駐リンクの受信を一手に引き受け、占有権を持つ1利用者だけに送受信させるバイトストリームです。
///
/// `AdapterLinkPort.dataDidReceive` は1つしか設定できないため、リンク1本につきこの型を1つだけ作り、
/// 監視用のコマンド(初期化・車両確認・VIN)とテレメトリ用のトランスポートはどちらもこの型の占有権を通して送受信します。
/// 占有者が替わるたびに受信バッファーを捨てるので、前の利用者の応答が次の利用者へ混ざりません。
/// 占有者がいない間に届いたバイトは捨てます。リンクの接続・停止は一切行いません。
@MainActor
final class AdapterLinkByteStream {
    /// 進行中の1件の読取です。
    private struct PendingRead {
        /// 読取ごとに一意な通し番号です。
        let id: UInt64
        /// 読取を始めた占有権の通し番号です。
        let leaseID: UInt64
        /// プロンプトまで待つ読取なら `true`、時間窓で集める読取なら `false`。
        let waitsForPrompt: Bool
        /// 読取結果の受け渡し先です。
        let continuation: CheckedContinuation<AdapterLinkCollectedBytes, any Error>
        /// 期限とリンク状態の監視タスクです。
        let watchdog: Task<Void, Never>
    }

    /// 送受信先の常駐リンクです。
    private let link: any AdapterLinkPort
    /// 待機上限と容量です。
    private let limits: AdapterLinkByteStreamLimits
    /// 待機に使う処理です。
    private let sleep: @Sendable (Duration) async throws -> Void
    /// 占有権の待ち行列です。
    private let leases: AdapterLinkByteStreamLeaseQueue
    /// 現在の占有者向けの受信バッファーです。
    private var buffer: AdapterLinkPromptBuffer
    /// 受信がバッファー上限を超えて応答境界を失ったかどうかです。占有者が替わると戻ります。
    private var hasOverflowed = false
    /// 進行中の読取です。
    private var pendingRead: PendingRead?
    /// 最後に払い出した読取の通し番号です。
    private var lastReadID: UInt64 = 0

    /// 常駐リンクの受信先を自分に設定して生成します。
    ///
    /// 責務: リンクの `dataDidReceive` を占有し、受信の分配をこの型へ一本化します。
    /// - Parameters:
    ///   - link: 送受信先の常駐リンク。`dataDidReceive` は上書きされます。
    ///   - limits: 待機上限と容量。
    ///   - sleep: 待機に使う処理。キャンセル時は throw すること。テストは実時間を待たない実装を渡します。
    init(
        link: any AdapterLinkPort,
        limits: AdapterLinkByteStreamLimits = .standard,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.link = link
        self.limits = limits
        self.sleep = sleep
        leases = AdapterLinkByteStreamLeaseQueue(timeout: limits.leaseTimeout, sleep: sleep)
        buffer = AdapterLinkPromptBuffer(capacity: limits.receiveBufferCapacity)
        leases.holderDidChange = { [weak self] in
            self?.discardBufferedBytes()
        }
        link.dataDidReceive = { [weak self] data in
            self?.receive(data)
        }
    }

    /// 常駐リンクの現在の状態です。
    var linkState: AdapterLinkState { link.state }

    /// 送受信の占有権を取得します。
    ///
    /// 責務: リンクが `ready` の時だけ、到着順で1利用者に占有権を渡します。
    /// - Returns: 取得した占有権。
    /// - Throws: `ready` でなければ `.notReady`、待機上限超過は `.leaseUnavailable`、キャンセル時は `CancellationError`。
    func acquireLease() async throws -> AdapterLinkByteStreamLease {
        guard link.state == .ready else { throw AdapterLinkByteStreamError.notReady }
        return try await leases.acquire()
    }

    /// 占有権を解放します。
    ///
    /// 責務: 現在の占有者の読取を終わらせて占有権を手放します。リンクは止めません。
    /// - Parameter lease: 解放する占有権。現在の占有者でなければ何もしません。
    func release(_ lease: AdapterLinkByteStreamLease) {
        guard leases.holder == lease else { return }
        if let pendingRead, pendingRead.leaseID == lease.id {
            finishRead(pendingRead.id, with: .failure(AdapterLinkByteStreamError.leaseNotHeld))
        }
        leases.release(lease)
    }

    /// 占有者としてリンクへバイト列を書き込みます。
    ///
    /// 責務: 占有権とリンク状態を確認してから1件のバイト列をリンクへ渡します。
    /// - Parameters:
    ///   - data: 送信するバイト列。
    ///   - lease: 現在の占有権。
    /// - Throws: 占有者でなければ `.leaseNotHeld`、`ready` でなければ `.notReady`、書き込み失敗は `.writeFailed`。
    func write(_ data: Data, lease: AdapterLinkByteStreamLease) async throws {
        guard leases.holder == lease else { throw AdapterLinkByteStreamError.leaseNotHeld }
        guard link.state == .ready else { throw AdapterLinkByteStreamError.notReady }
        do {
            try await link.write(data)
        } catch let error as AdapterLinkWriteError {
            throw AdapterLinkByteStreamError.writeFailed(error)
        }
    }

    /// 次のプロンプト `>` までの受信バイトを返します。
    ///
    /// 責務: 分割して届いたバイトを最初の `>` まで結合し、残りを次の応答のために残します。
    /// - Parameters:
    ///   - lease: 現在の占有権。
    ///   - timeout: プロンプトを待つ上限。
    /// - Returns: `>` を含む応答バイト。
    /// - Throws: 期限切れは `.responseTimedOut`、切断は `.linkLost`、ほか占有・読取の型付きエラーと `CancellationError`。
    func readUntilPrompt(lease: AdapterLinkByteStreamLease, timeout: Duration) async throws -> Data {
        try await read(lease: lease, duration: timeout, waitsForPrompt: true).data
    }

    /// 時間窓の間に届いた受信バイトを集めます。
    ///
    /// 責務: プロンプトの無い連続受信(受信監視など)を、窓の終了かプロンプト到着のどちらか早い方まで集めます。
    /// - Parameters:
    ///   - lease: 現在の占有権。
    ///   - window: 集める時間。
    /// - Returns: 集めたバイトと、プロンプトで終わったかどうか。
    /// - Throws: 切断は `.linkLost`、ほか占有・読取の型付きエラーと `CancellationError`。
    func collect(lease: AdapterLinkByteStreamLease, window: Duration) async throws -> AdapterLinkCollectedBytes {
        try await read(lease: lease, duration: window, waitsForPrompt: false)
    }

    /// 読取を始めます。
    ///
    /// 責務: 前提を検証し、溜まっている応答で完結すれば即座に返し、そうでなければ期限監視付きで待ちます。
    /// - Parameters:
    ///   - lease: 現在の占有権。
    ///   - duration: 待つ上限または集める時間。
    ///   - waitsForPrompt: プロンプトまで待つなら `true`。
    /// - Returns: 読取結果。
    /// - Throws: 型付きの読取エラーまたは `CancellationError`。
    private func read(
        lease: AdapterLinkByteStreamLease,
        duration: Duration,
        waitsForPrompt: Bool
    ) async throws -> AdapterLinkCollectedBytes {
        try validateReadPreconditions(lease: lease)
        if let response = buffer.takeThroughPrompt() {
            return AdapterLinkCollectedBytes(data: response, endedWithPrompt: true)
        }
        lastReadID &+= 1
        let readID = lastReadID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                beginWaiting(readID: readID, leaseID: lease.id, duration: duration, waitsForPrompt: waitsForPrompt, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishRead(readID, with: .failure(CancellationError()))
            }
        }
    }

    /// 読取の前提を検証します。
    ///
    /// 責務: 占有権・読取の重複・応答境界・リンク状態のいずれかが崩れていれば読取を始めさせません。
    /// - Parameter lease: 現在の占有権。
    /// - Throws: 崩れている前提に対応する `AdapterLinkByteStreamError`。
    private func validateReadPreconditions(lease: AdapterLinkByteStreamLease) throws {
        guard leases.holder == lease else { throw AdapterLinkByteStreamError.leaseNotHeld }
        guard pendingRead == nil else { throw AdapterLinkByteStreamError.readInProgress }
        guard !hasOverflowed else { throw AdapterLinkByteStreamError.receiveBufferOverflow }
        guard link.state == .ready else { throw AdapterLinkByteStreamError.linkLost }
    }

    /// 読取の待機を登録します。
    ///
    /// 責務: キャンセル済みなら即座に失敗させ、そうでなければ期限監視を付けて進行中の読取にします。
    /// - Parameters:
    ///   - readID: 読取の通し番号。
    ///   - leaseID: 読取を始めた占有権の通し番号。
    ///   - duration: 待つ上限または集める時間。
    ///   - waitsForPrompt: プロンプトまで待つなら `true`。
    ///   - continuation: 読取結果の受け渡し先。
    private func beginWaiting(
        readID: UInt64,
        leaseID: UInt64,
        duration: Duration,
        waitsForPrompt: Bool,
        continuation: CheckedContinuation<AdapterLinkCollectedBytes, any Error>
    ) {
        guard !Task.isCancelled else {
            continuation.resume(throwing: CancellationError())
            return
        }
        let watchdog = makeWatchdog(readID: readID, checkCount: limits.checkCount(for: duration))
        pendingRead = PendingRead(
            id: readID,
            leaseID: leaseID,
            waitsForPrompt: waitsForPrompt,
            continuation: continuation,
            watchdog: watchdog
        )
    }

    /// 読取の期限とリンク状態を監視するタスクを作ります。
    ///
    /// 責務: 確認間隔ごとにリンク状態を見て切断なら失敗させ、上限回数に達したら期限切れか時間窓の終了として読取を終わらせます。
    /// - Parameters:
    ///   - readID: 監視する読取の通し番号。
    ///   - checkCount: 確認する上限回数。
    /// - Returns: 監視タスク。
    private func makeWatchdog(readID: UInt64, checkCount: Int) -> Task<Void, Never> {
        let interval = limits.linkCheckInterval
        let sleep = sleep
        return Task { @MainActor [weak self] in
            for _ in 0..<checkCount {
                do { try await sleep(interval) } catch { return }
                guard let self, self.pendingRead?.id == readID else { return }
                if self.link.state != .ready {
                    self.finishRead(readID, with: .failure(AdapterLinkByteStreamError.linkLost))
                    return
                }
            }
            self?.finishExpiredRead(readID)
        }
    }

    /// 上限時間に達した読取を終わらせます。
    ///
    /// 責務: プロンプト待ちなら期限切れで失敗させ、時間窓の読取ならそれまでに集めたバイトを返します。
    /// - Parameter readID: 終わらせる読取の通し番号。
    private func finishExpiredRead(_ readID: UInt64) {
        guard let pendingRead, pendingRead.id == readID else { return }
        if pendingRead.waitsForPrompt {
            finishRead(readID, with: .failure(AdapterLinkByteStreamError.responseTimedOut))
        } else {
            finishRead(readID, with: .success(AdapterLinkCollectedBytes(data: buffer.takeAll(), endedWithPrompt: false)))
        }
    }

    /// 進行中の読取を結果で終わらせます。
    ///
    /// 責務: 指定番号の読取がまだ進行中の場合だけ、監視を止めて結果を1回だけ渡します。
    /// - Parameters:
    ///   - readID: 終わらせる読取の通し番号。
    ///   - result: 渡す結果。
    private func finishRead(_ readID: UInt64, with result: Result<AdapterLinkCollectedBytes, any Error>) {
        guard let pendingRead, pendingRead.id == readID else { return }
        self.pendingRead = nil
        pendingRead.watchdog.cancel()
        pendingRead.continuation.resume(with: result)
    }

    /// リンクから届いたバイトを受け取ります。
    ///
    /// 責務: 占有者がいる時だけ溜め、プロンプトが揃えば読取を完了させます。上限超過の場合、時間窓の読取は
    /// それまでの受信で早めに終わらせ(受信監視の停止手順を続けられるように)、それ以外は応答境界を失ったものとして失敗させます。
    /// - Parameter data: 届いたバイト。
    private func receive(_ data: Data) {
        guard leases.holder != nil, !hasOverflowed else { return }
        if let pendingRead, !pendingRead.waitsForPrompt, buffer.bytes.count + data.count > buffer.capacity {
            finishRead(pendingRead.id, with: .success(Self.collectedBytes(buffer.takeAll() + data)))
            return
        }
        guard buffer.append(data) else {
            buffer.removeAll()
            hasOverflowed = true
            if let pendingRead {
                finishRead(pendingRead.id, with: .failure(AdapterLinkByteStreamError.receiveBufferOverflow))
            }
            return
        }
        guard let pendingRead, let response = buffer.takeThroughPrompt() else { return }
        finishRead(pendingRead.id, with: .success(AdapterLinkCollectedBytes(data: response, endedWithPrompt: true)))
    }

    /// 時間窓の読取を早めに終えるときの結果を作ります。
    ///
    /// 責務: プロンプトを含めばそこまでを、含まなければ全体を、プロンプトの有無とともに返します。
    /// - Parameter data: 窓の間に集めた受信。
    /// - Returns: 読取結果。
    private static func collectedBytes(_ data: Data) -> AdapterLinkCollectedBytes {
        guard let promptIndex = data.firstIndex(of: AdapterLinkPromptBuffer.promptByte) else {
            return AdapterLinkCollectedBytes(data: data, endedWithPrompt: false)
        }
        return AdapterLinkCollectedBytes(data: Data(data[...promptIndex]), endedWithPrompt: true)
    }

    /// 受信バッファーを捨てます。
    ///
    /// 責務: 占有者が替わったときに前の利用者の受信と境界喪失の記録を消します。
    private func discardBufferedBytes() {
        buffer.removeAll()
        hasOverflowed = false
    }
}

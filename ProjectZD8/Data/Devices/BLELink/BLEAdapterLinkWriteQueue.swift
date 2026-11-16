#if os(iOS) || os(macOS)
import Foundation

/// `ready` のリンクへの書き込みを呼び出し順のチャンク列として送り、完了通知・送信可能通知に合わせて進めます。
///
/// 送信待ちが進まない(応答ありの完了通知・応答なしの送信可能通知が届かない)まま期限を超えたら、全ての送信待ちを
/// `AdapterLinkWriteError.timedOut` で終えて `writeDidTimeOut` を呼びます。完了通知はチャンクを識別しないため、
/// 遅れて届いた通知が次の送信待ちに当たらないよう、該当の1件だけでなく全件を失敗させます。
@MainActor
final class BLEAdapterLinkWriteQueue {
    /// 書き込み先のペリフェラルとCharacteristicです。
    struct Target {
        /// 書き込むペリフェラルです。
        let peripheral: any BLEPeripheralRole
        /// Characteristicを持つService UUIDです。
        let serviceUUID: String
        /// 書き込むCharacteristic UUIDです。
        let characteristicUUID: String
        /// 書き込み種別です。
        let kind: BLEWriteKind
    }

    /// 1回の `write` 呼び出しに対応する送信待ちです。
    private struct Job {
        /// 送信するチャンク列です。
        let chunks: [Data]
        /// 次に送るチャンクの位置です。
        var nextIndex = 0
        /// 呼び出し元へ結果を返す継続です。
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// 書き込みを分割する純粋型です。
    private let chunker = BLEWriteChunker()
    /// 現在の書き込み先です。`nil` の間は書き込みを受け付けません。
    private var target: Target?
    /// 呼び出し順の送信待ちです。
    private var jobs: [Job] = []
    /// 応答あり書き込みの完了通知を待っているかどうかです。
    private var isAwaitingResponse = false
    /// 送信待ちが進まないまま待つ上限時間です。
    private let completionTimeout: Duration
    /// 送信待ちが進まない時間の期限です。探索用の期限とは別のインスタンスです。
    private let stallDeadline: BLEAdapterLinkDeadline

    /// 送信待ちが期限内に進まず全件をタイムアウトで終えた後に呼ばれる処理です。リンク障害として扱うために使います。
    var writeDidTimeOut: (@MainActor () -> Void)?

    /// 期限と待機手段を固定して生成します。
    ///
    /// 責務: 送信待ちが進まない時間の上限と、その期限を待つ処理を保持します。
    /// - Parameters:
    ///   - completionTimeout: 送信待ちが進まないまま待つ上限。既定は `BLEAdapterLinkLimits.standardWriteCompletionTimeout`。
    ///   - sleep: 期限待ちに使う待機処理。テストは実時間を待たない実装を渡します。
    init(
        completionTimeout: Duration = BLEAdapterLinkLimits.standardWriteCompletionTimeout,
        sleep: @escaping BLEAdapterLinkDeadline.Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.completionTimeout = completionTimeout
        stallDeadline = BLEAdapterLinkDeadline(sleep: sleep)
    }

    /// 書き込みを受け付ける状態かどうかです。
    var isActive: Bool { target != nil }

    /// 書き込み先を設定して受け付けを始めます。
    ///
    /// 責務: `ready` になった送受信路を書き込み先として保持します。
    /// - Parameter target: 書き込み先。
    func activate(_ target: Target) {
        stallDeadline.cancel()
        self.target = target
        isAwaitingResponse = false
    }

    /// 1件のバイト列を送信待ちに加え、全チャンクを送り終えるまで待ちます。
    ///
    /// 責務: 呼び出し順を保ってチャンク列を送信待ちへ追加し、結果を呼び出し元へ返します。
    /// - Parameter data: 送信するバイト列。
    /// - Throws: 受け付け前は `AdapterLinkWriteError.notReady`、分割できなければ `writeFailed`、破棄時は破棄理由。
    func enqueue(_ data: Data) async throws {
        guard let target else { throw AdapterLinkWriteError.notReady }
        let chunks: [Data]
        do {
            chunks = try chunker.chunks(of: data, maximumLength: target.peripheral.maximumWriteValueLength(for: target.kind))
        } catch {
            throw AdapterLinkWriteError.writeFailed(description: String(describing: error))
        }
        guard !chunks.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            jobs.append(Job(chunks: chunks, continuation: continuation))
            advance()
        }
    }

    /// 応答あり書き込みの完了通知を反映します。
    ///
    /// 責務: 完了したチャンクの結果で送信待ちを進め、失敗なら該当呼び出しを失敗で終えます。
    /// - Parameter errorDescription: OSのエラー説明。成功時は `nil`。
    func handleWriteCompleted(errorDescription: String?) {
        guard isAwaitingResponse, !jobs.isEmpty else { return }
        isAwaitingResponse = false
        if let errorDescription {
            jobs.removeFirst().continuation.resume(throwing: AdapterLinkWriteError.writeFailed(description: errorDescription))
        } else if jobs[0].nextIndex >= jobs[0].chunks.count {
            jobs.removeFirst().continuation.resume()
        }
        advance(progressed: true)
    }

    /// 応答なし書き込みの送信可能通知を反映します。
    ///
    /// 責務: 送信可否待ちで止まっていたチャンク送信を再開します。
    func handleReadyToSend() {
        advance()
    }

    /// 受け付けを止め、全ての送信待ちを指定エラーで終えます。
    ///
    /// 責務: 書き込み先を外して待機中の全呼び出しを明示的なエラーで完了させます。
    /// - Parameter error: 呼び出し元へ返すエラー。
    func failAll(with error: AdapterLinkWriteError) {
        stallDeadline.cancel()
        target = nil
        isAwaitingResponse = false
        let pending = jobs
        jobs.removeAll()
        pending.forEach { $0.continuation.resume(throwing: error) }
    }

    /// 送れるだけ送り、送信待ちが残る間だけ進まない時間の期限を設定します。
    ///
    /// 責務: 送信を進め、送信待ちが無くなれば期限を捨て、進んだ時か期限が無い時だけ期限を設定し直します。
    /// 進まないまま並んだ送信待ちでは期限を延ばしません。
    /// - Parameter progressed: 呼び出し前に完了通知で送信待ちが進んだかどうか。
    private func advance(progressed: Bool = false) {
        let sentChunk = pump()
        guard target != nil, !jobs.isEmpty else {
            stallDeadline.cancel()
            return
        }
        guard progressed || sentChunk || !stallDeadline.isArmed else { return }
        stallDeadline.arm(after: completionTimeout) { [weak self] in
            self?.handleStallDeadlineExpired()
        }
    }

    /// 送信待ちが期限内に進まなかったことを反映します。
    ///
    /// 責務: 全ての送信待ちを `timedOut` で終えて受け付けを止め、リンク障害として通知します。
    private func handleStallDeadlineExpired() {
        guard target != nil, !jobs.isEmpty else { return }
        failAll(with: .timedOut)
        writeDidTimeOut?()
    }

    /// 送れるだけのチャンクを先頭の送信待ちから順に送ります。
    ///
    /// 責務: 応答待ち・送信不可でなければ次のチャンクを1つずつ書き込みます。総チャンク数で必ず終わります。
    /// - Returns: 1つ以上のチャンクを送ったか、送信待ちを1件以上完了させたなら `true`。
    @discardableResult
    private func pump() -> Bool {
        var progressed = false
        while let target, !isAwaitingResponse, !jobs.isEmpty {
            let index = jobs[0].nextIndex
            guard index < jobs[0].chunks.count else {
                jobs.removeFirst().continuation.resume()
                progressed = true
                continue
            }
            if target.kind == .withoutResponse, !target.peripheral.canSendWriteWithoutResponse {
                return progressed
            }
            progressed = true
            jobs[0].nextIndex = index + 1
            if target.kind == .withResponse {
                isAwaitingResponse = true
            }
            target.peripheral.writeValue(
                jobs[0].chunks[index],
                characteristicUUID: target.characteristicUUID,
                serviceUUID: target.serviceUUID,
                kind: target.kind
            )
        }
        return progressed
    }
}
#endif

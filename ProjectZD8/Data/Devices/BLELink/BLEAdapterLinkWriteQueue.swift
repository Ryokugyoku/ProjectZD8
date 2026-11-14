#if os(iOS) || os(macOS)
import Foundation

/// `ready` のリンクへの書き込みを呼び出し順のチャンク列として送り、完了通知・送信可能通知に合わせて進めます。
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

    /// 書き込みを受け付ける状態かどうかです。
    var isActive: Bool { target != nil }

    /// 書き込み先を設定して受け付けを始めます。
    ///
    /// 責務: `ready` になった送受信路を書き込み先として保持します。
    /// - Parameter target: 書き込み先。
    func activate(_ target: Target) {
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
            pump()
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
        pump()
    }

    /// 応答なし書き込みの送信可能通知を反映します。
    ///
    /// 責務: 送信可否待ちで止まっていたチャンク送信を再開します。
    func handleReadyToSend() {
        pump()
    }

    /// 受け付けを止め、全ての送信待ちを指定エラーで終えます。
    ///
    /// 責務: 書き込み先を外して待機中の全呼び出しを明示的なエラーで完了させます。
    /// - Parameter error: 呼び出し元へ返すエラー。
    func failAll(with error: AdapterLinkWriteError) {
        target = nil
        isAwaitingResponse = false
        let pending = jobs
        jobs.removeAll()
        pending.forEach { $0.continuation.resume(throwing: error) }
    }

    /// 送れるだけのチャンクを先頭の送信待ちから順に送ります。
    ///
    /// 責務: 応答待ち・送信不可でなければ次のチャンクを1つずつ書き込みます。総チャンク数で必ず終わります。
    private func pump() {
        while let target, !isAwaitingResponse, !jobs.isEmpty {
            let index = jobs[0].nextIndex
            guard index < jobs[0].chunks.count else {
                jobs.removeFirst().continuation.resume()
                continue
            }
            if target.kind == .withoutResponse, !target.peripheral.canSendWriteWithoutResponse {
                return
            }
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
    }
}
#endif

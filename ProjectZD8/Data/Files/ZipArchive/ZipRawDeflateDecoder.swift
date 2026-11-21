import Compression
import Foundation

/// ZIP の raw deflate(RFC 1951)を、Compression の `COMPRESSION_ZLIB` で固定長のバッファを使って逐次に展開します。
///
/// SDK の `compression.h` は `COMPRESSION_ZLIB` を「見出しなしの raw DEFLATE」と定めているので、ZIP の deflate をそのまま渡せます。
/// 入力と出力のバッファは一定の大きさで、展開後の全体をメモリに載せません。
nonisolated struct ZipRawDeflateDecoder: Sendable {
    /// 入力バッファの大きさ。
    let inputChunkSize: Int
    /// 出力バッファの大きさ。
    let outputChunkSize: Int

    /// バッファの大きさを決めます。
    ///
    /// 責務: 0 以下の値を 1 に切り上げて保持します。
    /// - Parameters:
    ///   - inputChunkSize: 入力バッファの大きさ。
    ///   - outputChunkSize: 出力バッファの大きさ。
    init(inputChunkSize: Int, outputChunkSize: Int) {
        self.inputChunkSize = max(1, inputChunkSize)
        self.outputChunkSize = max(1, outputChunkSize)
    }

    /// 圧縮データを最後まで展開し、塊ごとに `output` へ渡します。
    ///
    /// 責務: 展開の終わり(END)か失敗まで、入力の補充と展開を繰り返します。
    /// 1回の繰り返しで入力も出力も進まなければ、壊れた入力とみなして止めます(回り続けません)。
    /// - Parameters:
    ///   - input: 圧縮データの読み取り器。
    ///   - output: 展開した塊の照合と受け渡し。
    ///   - progress: 読んだ圧縮バイトの累計を受け取る処理。
    ///   - consume: 展開した塊を受け取る処理。
    /// - Throws: 展開の失敗・停滞は `inflateFailed`。取り消しは `CancellationError`。その他は読み取りと `consume` の失敗。
    func decode(
        input: inout ZipCompressedInputReader,
        output: inout ZipEntryOutputVerifier,
        progress: (UInt64) -> Void,
        consume: (UnsafeRawBufferPointer) throws -> Void
    ) throws {
        let source = UnsafeMutablePointer<UInt8>.allocate(capacity: inputChunkSize)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: outputChunkSize)
        defer {
            source.deallocate()
            destination.deallocate()
        }
        var stream = compression_stream(dst_ptr: destination, dst_size: 0, src_ptr: source, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw ZipArchiveError.inflateFailed
        }
        defer { compression_stream_destroy(&stream) }
        var finished = false
        while !finished {
            try Task.checkCancellation()
            let refilled = try refill(&stream, buffer: source, from: &input, progress: progress)
            finished = try process(&stream, destination: destination, isFinal: input.remaining == 0, refilled: refilled) {
                try output.accept($0, consume: consume)
            }
        }
    }

    /// 入力バッファが空なら、次の塊を読んで詰めます。
    ///
    /// 責務: 入力の補充と進捗の通知を行います。
    /// - Parameters:
    ///   - stream: 展開の状態。
    ///   - buffer: 入力バッファ。
    ///   - input: 圧縮データの読み取り器。
    ///   - progress: 読んだ圧縮バイトの累計を受け取る処理。
    /// - Returns: 補充したら `true`。
    /// - Throws: 読み取りの失敗。
    private func refill(
        _ stream: inout compression_stream,
        buffer: UnsafeMutablePointer<UInt8>,
        from input: inout ZipCompressedInputReader,
        progress: (UInt64) -> Void
    ) throws -> Bool {
        guard stream.src_size == 0, input.remaining > 0 else { return false }
        let chunk = try input.nextChunk()
        chunk.copyBytes(to: buffer, count: chunk.count)
        stream.src_ptr = UnsafePointer(buffer)
        stream.src_size = chunk.count
        progress(input.consumed)
        return true
    }

    /// 展開を1回進め、出た塊を渡します。
    ///
    /// 責務: 1回の `compression_stream_process` の結果を、終わり・続き・失敗に振り分けます。
    /// - Parameters:
    ///   - stream: 展開の状態。
    ///   - destination: 出力バッファ。
    ///   - isFinal: 入力をすべて読み終えたか。
    ///   - refilled: この回に入力を補充したか。
    ///   - emit: 出た塊を受け取る処理。
    /// - Returns: 展開が終わったら `true`。
    /// - Throws: 失敗・停滞は `inflateFailed`。`emit` の失敗はそのまま。
    private func process(
        _ stream: inout compression_stream,
        destination: UnsafeMutablePointer<UInt8>,
        isFinal: Bool,
        refilled: Bool,
        emit: (UnsafeRawBufferPointer) throws -> Void
    ) throws -> Bool {
        let sourceBefore = stream.src_size
        stream.dst_ptr = destination
        stream.dst_size = outputChunkSize
        let flags = isFinal ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
        let status = compression_stream_process(&stream, flags)
        let produced = outputChunkSize - stream.dst_size
        try emit(UnsafeRawBufferPointer(start: destination, count: produced))
        switch status {
        case COMPRESSION_STATUS_END:
            return true
        case COMPRESSION_STATUS_OK:
            let advanced = produced > 0 || stream.src_size != sourceBefore || refilled
            guard advanced else { throw ZipArchiveError.inflateFailed }
            return false
        default:
            throw ZipArchiveError.inflateFailed
        }
    }
}

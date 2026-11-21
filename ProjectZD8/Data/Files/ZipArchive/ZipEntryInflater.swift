import Foundation

/// ZIP の1エントリを、メモリに全部載せずに読みながら展開し、塊ごとに受け手へ渡します。
///
/// - 格納(方式0)と deflate(方式8)だけを受け付けます。暗号化と他の方式は明示的に失敗させます。
/// - 本体の開始位置は、ローカル見出し(30 B)の名前長と拡張長を読み直して決めます(中央側と違うことがあるため)。
/// - 大きさと CRC32 は中央ディレクトリの値で照合します。宣言を超えた出力と、上限を超える宣言は止めます。
/// - 塊を読むたびに `Task.checkCancellation()` で取り消しに応じます。
nonisolated struct ZipEntryInflater: Sendable {
    /// 1回に読む圧縮データの最大のバイト数。
    let inputChunkSize: Int
    /// 1回に受け手へ渡す展開後の最大のバイト数。
    let outputChunkSize: Int
    /// 受け付ける展開後の大きさの上限。
    let maximumUncompressedSize: UInt64
    /// 範囲を過不足なく読む部品。
    private let regionReader = ZipFileRegionReader()

    /// バッファの大きさと、展開後の大きさの上限を決めます。
    ///
    /// 責務: 展開の設定を保持します(0 以下のバッファの大きさは 1 にします)。
    /// - Parameters:
    ///   - inputChunkSize: 1回に読む圧縮データの最大のバイト数。既定 64 KiB。
    ///   - outputChunkSize: 1回に渡す展開後の最大のバイト数。既定 256 KiB。
    ///   - maximumUncompressedSize: 受け付ける展開後の大きさの上限。既定 2 GiB。
    init(inputChunkSize: Int = 65_536, outputChunkSize: Int = 262_144, maximumUncompressedSize: UInt64 = 2 << 30) {
        self.inputChunkSize = max(1, inputChunkSize)
        self.outputChunkSize = max(1, outputChunkSize)
        self.maximumUncompressedSize = maximumUncompressedSize
    }

    /// エントリを展開し、塊を順に `consume` へ渡します。
    ///
    /// 責務: エントリの検査、本体の位置決め、方式ごとの展開、最後の照合を順に行います。
    /// - Parameters:
    ///   - entry: 中央ディレクトリから読んだエントリ。
    ///   - file: 読み取る ZIP ファイル。
    ///   - progress: 読んだ圧縮バイトの累計を受け取る処理(最後は圧縮後の大きさに一致します)。
    ///   - consume: 展開した塊を受け取る処理。塊は呼び出しの間だけ有効です。
    /// - Throws: `ZipArchiveError`、取り消しの `CancellationError`、`consume` と `FileHandle` の失敗。
    func stream(
        _ entry: ZipArchiveEntry,
        from file: FileHandle,
        progress: (UInt64) -> Void,
        consume: (UnsafeRawBufferPointer) throws -> Void
    ) throws {
        try validate(entry)
        let dataStart = try dataOffset(of: entry, in: file)
        var input = try ZipCompressedInputReader(file: file, start: dataStart, length: entry.compressedSize, chunkSize: inputChunkSize)
        var output = ZipEntryOutputVerifier(entry: entry)
        if entry.compressionMethod == Self.storedMethod {
            try copyStored(input: &input, output: &output, progress: progress, consume: consume)
        } else {
            let decoder = ZipRawDeflateDecoder(inputChunkSize: inputChunkSize, outputChunkSize: outputChunkSize)
            try decoder.decode(input: &input, output: &output, progress: progress, consume: consume)
        }
        try output.verify()
    }

    /// 展開できるエントリかを検査します。
    ///
    /// 責務: 暗号化・方式・大きさの上限を、読み始める前に確かめます。
    /// - Parameter entry: 検査するエントリ。
    /// - Throws: `encryptedEntry`、`unsupportedCompressionMethod`、`entryTooLarge`、格納で大きさが食い違えば `sizeMismatch`。
    private func validate(_ entry: ZipArchiveEntry) throws {
        guard !entry.isEncrypted else { throw ZipArchiveError.encryptedEntry }
        guard [Self.storedMethod, Self.deflateMethod].contains(entry.compressionMethod) else {
            throw ZipArchiveError.unsupportedCompressionMethod(entry.compressionMethod)
        }
        guard entry.uncompressedSize <= maximumUncompressedSize else { throw ZipArchiveError.entryTooLarge }
        let storedSizesDiffer = entry.compressionMethod == Self.storedMethod && entry.compressedSize != entry.uncompressedSize
        guard !storedSizesDiffer else { throw ZipArchiveError.sizeMismatch }
    }

    /// ローカル見出しを読み直し、圧縮データの開始位置を求めます。
    ///
    /// 責務: ローカル見出しの署名を確かめ、名前長と拡張長から本体の位置を決め、範囲がファイルに収まるかを確かめます。
    /// - Parameters:
    ///   - entry: 展開するエントリ。
    ///   - file: 読み取る ZIP ファイル。
    /// - Returns: 圧縮データの、ファイル先頭からの位置。
    /// - Throws: 署名の不一致は `corruptLocalHeader`、範囲がファイルを超えれば `truncated`。
    private func dataOffset(of entry: ZipArchiveEntry, in file: FileHandle) throws -> UInt64 {
        let fileSize = try regionReader.size(of: file)
        guard entry.localHeaderOffset <= fileSize, fileSize - entry.localHeaderOffset >= UInt64(Self.localHeaderLength) else {
            throw ZipArchiveError.truncated
        }
        let header = ZipLittleEndianBytes(try regionReader.read(file, at: entry.localHeaderOffset, count: Self.localHeaderLength))
        guard header.uint32(at: 0) == Self.localHeaderSignature,
              let nameLength = header.uint16(at: 26), let extraLength = header.uint16(at: 28) else {
            throw ZipArchiveError.corruptLocalHeader
        }
        let start = entry.localHeaderOffset + UInt64(Self.localHeaderLength) + UInt64(nameLength) + UInt64(extraLength)
        guard start <= fileSize, fileSize - start >= entry.compressedSize else { throw ZipArchiveError.truncated }
        return start
    }

    /// 格納(方式0)のデータを、出力の塊の大きさに分けてそのまま渡します。
    ///
    /// 責務: 残量が尽きるまで読み、塊ごとに照合して渡します(残量が毎回減るので必ず終わります)。
    /// - Parameters:
    ///   - input: 圧縮データ(= 本体)の読み取り器。
    ///   - output: 塊の照合と受け渡し。
    ///   - progress: 読んだバイトの累計を受け取る処理。
    ///   - consume: 塊を受け取る処理。
    /// - Throws: 取り消し・読み取り・照合・`consume` の失敗。
    private func copyStored(
        input: inout ZipCompressedInputReader,
        output: inout ZipEntryOutputVerifier,
        progress: (UInt64) -> Void,
        consume: (UnsafeRawBufferPointer) throws -> Void
    ) throws {
        while input.remaining > 0 {
            try Task.checkCancellation()
            let chunk = try input.nextChunk()
            progress(input.consumed)
            try chunk.withUnsafeBytes { bytes in
                for start in stride(from: 0, to: bytes.count, by: outputChunkSize) {
                    let piece = UnsafeRawBufferPointer(rebasing: bytes[start..<min(start + outputChunkSize, bytes.count)])
                    try output.accept(piece, consume: consume)
                }
            }
        }
    }

    /// 格納の方式番号。
    private static let storedMethod: UInt16 = 0
    /// deflate の方式番号。
    private static let deflateMethod: UInt16 = 8
    /// ローカル見出しの署名 `PK\3\4`。
    private static let localHeaderSignature: UInt32 = 0x0403_4B50
    /// ローカル見出しの固定部分の長さ。
    private static let localHeaderLength = 30
}

import Foundation

/// 展開した塊を受け手へ渡しながら、CRC32 と展開済みの大きさを数えて宣言と照合します。
///
/// 宣言の大きさを超えた時点で止めます(ZIP 爆弾の対策)。
nonisolated struct ZipEntryOutputVerifier: Sendable {
    /// 中央ディレクトリが宣言する展開後の大きさ。
    let expectedSize: UInt64
    /// 中央ディレクトリが宣言する CRC32。
    let expectedChecksum: UInt32
    /// これまでに渡したバイト数。
    private(set) var byteCount: UInt64 = 0
    /// これまでに渡したバイト列の CRC32。
    private var checksum = CRC32Checksum()

    /// 照合する宣言の値を受け取ります。
    ///
    /// 責務: エントリの宣言から照合の初期状態を作ります。
    /// - Parameter entry: 展開するエントリ。
    init(entry: ZipArchiveEntry) {
        expectedSize = entry.uncompressedSize
        expectedChecksum = entry.crc32
    }

    /// 展開した塊を数えてから受け手へ渡します。
    ///
    /// 責務: 大きさの上限を確かめ、CRC32 を更新し、塊を受け手へ渡します。
    /// - Parameters:
    ///   - bytes: 展開した塊。空なら何もしません。
    ///   - consume: 塊を受け取る処理。
    /// - Throws: 宣言を超えたら `ZipArchiveError.sizeMismatch`。`consume` の失敗はそのまま。
    mutating func accept(_ bytes: UnsafeRawBufferPointer, consume: (UnsafeRawBufferPointer) throws -> Void) throws {
        guard !bytes.isEmpty else { return }
        byteCount += UInt64(bytes.count)
        guard byteCount <= expectedSize else { throw ZipArchiveError.sizeMismatch }
        checksum.update(bytes)
        try consume(bytes)
    }

    /// 全体を渡し終えた後に、大きさと CRC32 を宣言と照合します。
    ///
    /// 責務: 短い出力と壊れた内容を、成功として扱わないようにします。
    /// - Throws: 大きさが違えば `sizeMismatch`、CRC32 が違えば `checksumMismatch`。
    func verify() throws {
        guard byteCount == expectedSize else { throw ZipArchiveError.sizeMismatch }
        guard checksum.value == expectedChecksum else { throw ZipArchiveError.checksumMismatch }
    }
}

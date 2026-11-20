import Foundation

/// エントリの圧縮データの範囲を、決まった大きさの塊で先頭から順に読みます。
///
/// 範囲の外は読みません。読み終えた量を進捗として数えます。
nonisolated struct ZipCompressedInputReader {
    /// 読み取る ZIP ファイル。
    private let file: FileHandle
    /// 1回に読む最大のバイト数。
    private let chunkSize: Int
    /// まだ読んでいないバイト数。
    private(set) var remaining: UInt64
    /// これまでに読んだバイト数の累計。
    private(set) var consumed: UInt64 = 0

    /// 圧縮データの範囲を指定して、先頭へ移動します。
    ///
    /// 責務: 読み取り位置を範囲の先頭に合わせ、残量を初期化します。
    /// - Parameters:
    ///   - file: 読み取る ZIP ファイル。
    ///   - start: 圧縮データの、ファイル先頭からの位置。
    ///   - length: 圧縮データの大きさ。
    ///   - chunkSize: 1回に読む最大のバイト数(1 以上)。
    /// - Throws: `FileHandle` の移動の失敗。
    init(file: FileHandle, start: UInt64, length: UInt64, chunkSize: Int) throws {
        self.file = file
        self.chunkSize = max(1, chunkSize)
        remaining = length
        try file.seek(toOffset: start)
    }

    /// 次の塊を読みます。
    ///
    /// 責務: 残量と塊の大きさの小さい方だけ読み、残量と累計を更新します。
    /// - Returns: 読んだ塊。残量が 0 なら空。
    /// - Throws: ファイルが途中で終わっていれば `ZipArchiveError.truncated`。`FileHandle` の失敗はそのまま。
    mutating func nextChunk() throws -> Data {
        let count = Int(min(UInt64(chunkSize), remaining))
        guard count > 0 else { return Data() }
        // `FileHandle` が返す塊は自動解放プールに残ることがあるため、塊ごとにプールを空けてメモリを一定に保ちます。
        let data = try autoreleasepool { try file.read(upToCount: count).map { Data($0) } } ?? Data()
        guard data.count == count else { throw ZipArchiveError.truncated }
        remaining -= UInt64(count)
        consumed += UInt64(count)
        return data
    }
}

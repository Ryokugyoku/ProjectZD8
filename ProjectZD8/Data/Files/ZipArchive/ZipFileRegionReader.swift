import Foundation

/// ZIP ファイルの指定範囲を、`FileHandle` から過不足なく読みます。
///
/// 宣言された範囲がファイルの外にかかる時は、短いデータを黙って返さず `truncated` にします。
nonisolated struct ZipFileRegionReader: Sendable {
    /// 状態を持たない読み取り器を作ります。
    ///
    /// 責務: 範囲読み取りの部品を構築します。
    init() {}

    /// ファイル全体の大きさを返します。
    ///
    /// 責務: 末尾へ移動して位置を読みます。
    /// - Parameter file: 読み取る ZIP ファイル。
    /// - Returns: ファイルのバイト数。
    /// - Throws: `FileHandle` の失敗。
    func size(of file: FileHandle) throws -> UInt64 {
        try file.seekToEnd()
    }

    /// 指定位置から指定バイト数をちょうど読みます。
    ///
    /// 責務: 移動と読み取りを行い、足りなければ失敗にします。
    /// - Parameters:
    ///   - file: 読み取る ZIP ファイル。
    ///   - offset: ファイル先頭からの位置。
    ///   - count: 読むバイト数。
    /// - Returns: 読んだバイト列(長さは `count`)。
    /// - Throws: 読めたバイト数が足りなければ `ZipArchiveError.truncated`。`FileHandle` の失敗はそのまま。
    func read(_ file: FileHandle, at offset: UInt64, count: Int) throws -> [UInt8] {
        guard count > 0 else { return [] }
        try file.seek(toOffset: offset)
        // `FileHandle` が返す塊は自動解放プールに残ることがあるため、読むたびにプールを空けます。
        let bytes = try autoreleasepool { try file.read(upToCount: count).map { [UInt8]($0) } } ?? []
        guard bytes.count == count else { throw ZipArchiveError.truncated }
        return bytes
    }
}

import Foundation

/// ZIP の見出しのバイト列から、リトルエンディアンの整数を範囲を確かめながら読みます。
///
/// 範囲外の位置は `nil` を返し、壊れた入力でも配列の外を読みません。
nonisolated struct ZipLittleEndianBytes: Sendable {
    /// 読み取る対象のバイト列。
    let bytes: [UInt8]

    /// 読み取る対象のバイト列を受け取ります。
    ///
    /// 責務: 見出しのバイト列を、整数の読み出し用に保持します。
    /// - Parameter bytes: ZIP の見出しを含むバイト列。
    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// 指定位置の16ビット値を読みます。
    ///
    /// 責務: 2バイトをリトルエンディアンとして組み立てます。
    /// - Parameter offset: 先頭からの位置。
    /// - Returns: 値。範囲外なら `nil`。
    func uint16(at offset: Int) -> UInt16? {
        guard let value = unsignedInteger(at: offset, byteCount: 2) else { return nil }
        return UInt16(truncatingIfNeeded: value)
    }

    /// 指定位置の32ビット値を読みます。
    ///
    /// 責務: 4バイトをリトルエンディアンとして組み立てます。
    /// - Parameter offset: 先頭からの位置。
    /// - Returns: 値。範囲外なら `nil`。
    func uint32(at offset: Int) -> UInt32? {
        guard let value = unsignedInteger(at: offset, byteCount: 4) else { return nil }
        return UInt32(truncatingIfNeeded: value)
    }

    /// 指定位置の16ビット値を読み、範囲外なら指定のエラーを投げます。
    ///
    /// 責務: 必須の欄を、分岐なしで読み出せるようにします。
    /// - Parameters:
    ///   - offset: 先頭からの位置。
    ///   - error: 範囲外の時に投げるエラー。
    /// - Returns: 値。
    /// - Throws: 範囲外なら `error`。
    func uint16(at offset: Int, orThrow error: ZipArchiveError) throws -> UInt16 {
        guard let value = uint16(at: offset) else { throw error }
        return value
    }

    /// 指定位置の32ビット値を読み、範囲外なら指定のエラーを投げます。
    ///
    /// 責務: 必須の欄を、分岐なしで読み出せるようにします。
    /// - Parameters:
    ///   - offset: 先頭からの位置。
    ///   - error: 範囲外の時に投げるエラー。
    /// - Returns: 値。
    /// - Throws: 範囲外なら `error`。
    func uint32(at offset: Int, orThrow error: ZipArchiveError) throws -> UInt32 {
        guard let value = uint32(at: offset) else { throw error }
        return value
    }

    /// 指定位置から指定の長さのバイト列を取り出します。
    ///
    /// 責務: 範囲を確かめて部分列を複製します。
    /// - Parameters:
    ///   - offset: 先頭からの位置。
    ///   - count: 取り出すバイト数。
    /// - Returns: 取り出したバイト列。範囲外なら `nil`。
    func bytes(at offset: Int, count: Int) -> [UInt8]? {
        guard contains(offset: offset, count: count) else { return nil }
        return Array(bytes[offset..<(offset + count)])
    }

    /// 指定位置の範囲がバイト列の中に収まるかを判定します。
    ///
    /// 責務: 負の位置・負の長さ・末尾超えを弾きます。
    /// - Parameters:
    ///   - offset: 先頭からの位置。
    ///   - count: バイト数。
    /// - Returns: 収まれば `true`。
    func contains(offset: Int, count: Int) -> Bool {
        offset >= 0 && count >= 0 && offset <= bytes.count && count <= bytes.count - offset
    }

    /// 指定位置から指定バイト数をリトルエンディアンの整数として読みます。
    ///
    /// 責務: 範囲の確認と、下位バイトからの組み立てを行います。
    /// - Parameters:
    ///   - offset: 先頭からの位置。
    ///   - byteCount: 読むバイト数(8 以下)。
    /// - Returns: 値。範囲外なら `nil`。
    private func unsignedInteger(at offset: Int, byteCount: Int) -> UInt64? {
        guard contains(offset: offset, count: byteCount) else { return nil }
        var value: UInt64 = 0
        for index in 0..<byteCount {
            value |= UInt64(bytes[offset + index]) << (8 * UInt64(index))
        }
        return value
    }
}

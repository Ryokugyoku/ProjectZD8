import Foundation

/// ZIP の中央ディレクトリから読んだ、1つのエントリの情報です。
///
/// 大きさと CRC32 は中央ディレクトリの値です(データ記述子の bit3 が立っていても使えます)。
/// 本体の開始位置は、ローカル見出しを読み直して決めます(`ZipEntryInflater`)。
nonisolated struct ZipArchiveEntry: Equatable, Sendable {
    /// ファイル名のバイト列(復号前)。
    let pathBytes: [UInt8]
    /// 汎用フラグ。bit0 が暗号化、bit3 がデータ記述子、bit11(0x800)が UTF-8 のファイル名です。
    let flags: UInt16
    /// 圧縮方式の番号。0 が格納、8 が deflate です。
    let compressionMethod: UInt16
    /// 展開後のバイト列の CRC32。
    let crc32: UInt32
    /// 圧縮後(ファイル上)の大きさ。
    let compressedSize: UInt64
    /// 展開後の大きさ。
    let uncompressedSize: UInt64
    /// ローカル見出しの、ファイル先頭からの位置。
    let localHeaderOffset: UInt64

    /// 名前が `/` で終わるフォルダのエントリかどうか。
    var isDirectory: Bool {
        pathBytes.last == UInt8(ascii: "/")
    }

    /// 暗号化されているかどうか(フラグの bit0)。
    var isEncrypted: Bool {
        flags & Self.encryptedFlag != 0
    }

    /// 復号したファイル名。
    ///
    /// フラグ 0x800 が立っていれば UTF-8 として読みます。立っていなければ、ASCII だけで書かれている時だけ読みます。
    /// 読めない場合は `nil` です(CP437 などの推測はしません)。
    var path: String? {
        if flags & Self.utf8NameFlag != 0 {
            return String(validating: pathBytes, as: UTF8.self)
        }
        guard pathBytes.allSatisfy({ $0 < 0x80 }) else { return nil }
        return String(decoding: pathBytes, as: UTF8.self)
    }

    /// 暗号化を示すフラグの値。
    private static let encryptedFlag: UInt16 = 0x0001
    /// ファイル名が UTF-8 であることを示すフラグの値。
    private static let utf8NameFlag: UInt16 = 0x0800
}

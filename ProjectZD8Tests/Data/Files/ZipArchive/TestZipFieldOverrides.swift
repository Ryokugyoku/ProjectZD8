import Foundation

/// 局所ヘッダーまたは中央ディレクトリの見出しのうち、異常系を作るために上書きする項目です(`nil` は正しい値のまま)。
nonisolated struct TestZipFieldOverrides {
    /// 圧縮方式。
    var method: UInt16?
    /// 汎用フラグ。
    var flags: UInt16?
    /// CRC32。
    var crc: UInt32?
    /// 圧縮後のサイズ(0xFFFFFFFF で ZIP64 の印になります)。
    var compressedSize: UInt32?
    /// 展開後のサイズ(0xFFFFFFFF で ZIP64 の印になります)。
    var uncompressedSize: UInt32?
    /// 局所ヘッダーの位置(中央ディレクトリだけで使います)。
    var localHeaderOffset: UInt32?
}

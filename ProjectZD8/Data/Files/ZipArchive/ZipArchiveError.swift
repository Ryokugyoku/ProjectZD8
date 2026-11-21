import Foundation

/// ZIP アーカイブの読み取りと展開で起きる失敗です。
///
/// 対応しない形式(ZIP64・分割・暗号化・未対応の圧縮方式)と、壊れた入力を区別して返します。
/// どの失敗も空のデータに潰さず、呼び出し元へそのまま伝えます。
nonisolated enum ZipArchiveError: Error, Equatable, Sendable {
    /// 終端の見出し(EOCD)が見つからず、ZIP として読めません。
    case notZipArchive
    /// 宣言された位置や大きさに対して、ファイルが途中で終わっています。
    case truncated
    /// ZIP64 の印(0xFFFF / 0xFFFFFFFF や ZIP64 の終端位置)が使われています。
    case unsupportedZip64
    /// 複数のディスクに分割された ZIP です。
    case multiDiskUnsupported
    /// 暗号化されたエントリです(フラグの bit0)。
    case encryptedEntry
    /// 格納(0)と deflate(8)以外の圧縮方式です。値は方式の番号です。
    case unsupportedCompressionMethod(UInt16)
    /// 中央ディレクトリの署名・長さ・位置が矛盾しています。
    case corruptCentralDirectory
    /// ローカル見出しの署名が一致しません。
    case corruptLocalHeader
    /// deflate の展開に失敗したか、展開が進まなくなりました。
    case inflateFailed
    /// 展開したバイト列の CRC32 が中央ディレクトリの値と一致しません。
    case checksumMismatch
    /// 展開後のバイト数が宣言の大きさと一致しないか、宣言を超えて出力されました。
    case sizeMismatch
    /// 宣言された展開後の大きさが、受け付ける上限を超えています。
    case entryTooLarge
}

/// セッションアーカイブの復号・検証の失敗です。
nonisolated enum SessionArchiveCodecError: Error, Equatable, Sendable {
    /// 圧縮バイト列のSHA-256が期待値と一致しない。
    case digestMismatch
    /// この版のアプリが読めない形式版だった。
    case unsupportedFormatVersion(Int)
    /// 展開またはJSONの復号に失敗した。
    case malformed
}

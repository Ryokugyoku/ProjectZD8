/// 接続履歴 alert の本文です。
enum ConnectionHistoryAlertMessage: Equatable, Sendable {
    /// 固定文言です。View 側でキーを `LocalizedStringKey` に包みます。
    case localized(key: String)
    /// Raw件数とバイト数を埋め込む書式付き文言です。
    ///
    /// `ConnectionHistoryRawSummaryMessageFormatter` で文字列化します。
    case rawSummary(formatKey: String, recordCount: Int64, byteCount: Int64)
}

import Foundation

/// JARTIC の配布 ZIP と CSV の形式が、想定と違う時の失敗です。
///
/// 配布元が形式を変えたことを示すので、手元のデータを壊さずに取り込みを止める判断に使います。
nonisolated enum JARTICArchiveFormatError: Error, Equatable, Sendable {
    /// 見出しに必須の列が無い。値は欠けていた列名です。
    case missingColumn(String)
    /// 1行目のデータの版が対応する版(`k_2.`)ではない。値は読めた版の文字列です。
    case unsupportedVersion(String)
    /// 見出しを Shift-JIS として復号できない。
    case headerNotDecodable
    /// ZIP に CSV のエントリが無い。
    case noCSVEntry
    /// ZIP に CSV のエントリが2つ以上ある。
    case multipleCSVEntries
}

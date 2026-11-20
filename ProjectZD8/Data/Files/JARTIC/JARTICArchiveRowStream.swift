import Foundation

/// 区切った CSV の行を順に受け取り、見出しの照合・版の確認・1行の解釈を行って、記録を渡す状態機械です。
///
/// - 1行目は見出しとして `JARTICCSVHeader` にします(必須の列が欠けていれば失敗)。
/// - 2行目(最初のデータ行)の版の列が `k_2.` で始まらなければ `unsupportedVersion` で止めます。
/// - データ行は `JARTICRegulationRowParser` で解釈し、結果を1件ずつ渡します。行を溜めません。
nonisolated struct JARTICArchiveRowStream {
    /// 対応する版の接頭辞。
    static let supportedVersionPrefix = "k_2."

    /// 読んだ見出しと、見出しから作った1行の解釈器。1行目を読むまでは `nil`。
    private var columns: (header: JARTICCSVHeader, parser: JARTICRegulationRowParser)?
    /// 最初のデータ行から読んだ版。データ行を読むまでは `nil`。
    private(set) var formatVersion: String?
    /// 読んだデータ行の数(見出しを除く。空行は区切りの段階で除かれます)。
    private(set) var totalRows = 0

    /// 見出しを読む前の状態を作ります。
    ///
    /// 責務: 空の状態から始めます。
    init() {}

    /// 1行を見出しかデータ行として処理します。
    ///
    /// 責務: 見出しが未読なら見出しにし、読んでいればデータ行として解釈して渡します。
    /// - Parameters:
    ///   - row: 区切った1行。
    ///   - deliver: 1行の解釈結果を受け取る処理。
    /// - Throws: 見出しと版の形式違い(`JARTICArchiveFormatError`)、`deliver` の失敗。
    mutating func accept(_ row: JARTICCSVRow, deliver: (RoadRegulationArchiveRecord) throws -> Void) throws {
        guard let columns else {
            let header = try JARTICCSVHeader(row: row)
            self.columns = (header, JARTICRegulationRowParser(header: header))
            return
        }
        if formatVersion == nil {
            formatVersion = try Self.supportedVersion(of: row, header: columns.header)
        }
        totalRows += 1
        try deliver(columns.parser.parse(row))
    }

    /// 入力の終わりに、見出しを読めたかを確かめます。
    ///
    /// 責務: 見出しの無い(空の)CSV を形式違いとして止めます。
    /// - Throws: 見出しが無ければ、最初の必須列の `JARTICArchiveFormatError.missingColumn`。
    func requireHeader() throws {
        guard columns == nil else { return }
        throw JARTICArchiveFormatError.missingColumn(JARTICColumnName.required.first ?? JARTICColumnName.formatVersion)
    }

    /// 最初のデータ行の版を読み、対応する版かを確かめます。
    ///
    /// 責務: 版の列を ASCII として読み、接頭辞 `k_2.` を確かめます。
    /// - Parameters:
    ///   - row: 最初のデータ行。
    ///   - header: 見出し。
    /// - Returns: 読んだ版の文字列(例 `k_2.1`)。
    /// - Throws: 対応しない版・読めない版は `JARTICArchiveFormatError.unsupportedVersion`(読めない時は空文字)。
    private static func supportedVersion(of row: JARTICCSVRow, header: JARTICCSVHeader) throws -> String {
        let version = header.index(of: JARTICColumnName.formatVersion).flatMap(row.asciiString) ?? ""
        guard version.hasPrefix(supportedVersionPrefix) else {
            throw JARTICArchiveFormatError.unsupportedVersion(version)
        }
        return version
    }
}

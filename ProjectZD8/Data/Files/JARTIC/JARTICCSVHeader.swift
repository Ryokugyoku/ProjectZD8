import Foundation

/// JARTIC の CSV の見出し行から作った、列名から列番号(0 始まり)を引く表です。
///
/// 見出しの各項目を Shift-JIS で復号し、前後の空白を除いた名前で引きます。同じ名前が2回あれば最初の列を使います。
/// 必須の列(`JARTICColumnName.required`)が1つでも欠けていれば作れません。
nonisolated struct JARTICCSVHeader: Sendable {
    /// 見出しの項目数(データ行の項目数と比べるため)。
    let fieldCount: Int
    /// 列名から列番号への表。
    private let indices: [String: Int]

    /// 見出し行から列名の表を作ります。
    ///
    /// 責務: 見出しを Shift-JIS で復号し、列名の表を作り、必須の列がそろっているかを確かめます。
    /// - Parameter row: CSV の1行目(見出し)。
    /// - Throws: 復号できなければ `JARTICArchiveFormatError.headerNotDecodable`。
    ///   必須の列が欠けていれば、`JARTICColumnName.required` の順で最初に欠けた名前の `missingColumn`。
    init(row: JARTICCSVRow) throws {
        let names = try Self.decodedNames(of: row)
        var indices: [String: Int] = [:]
        for (index, name) in names.enumerated() where indices[name] == nil {
            indices[name] = index
        }
        if let missing = JARTICColumnName.required.first(where: { indices[$0] == nil }) {
            throw JARTICArchiveFormatError.missingColumn(missing)
        }
        fieldCount = row.fieldCount
        self.indices = indices
    }

    /// 列名から列番号を引きます。
    ///
    /// 責務: 見出しにある列の位置を返します。
    /// - Parameter name: 列名(`JARTICColumnName` の値)。
    /// - Returns: 0 始まりの列番号。見出しに無ければ `nil`。
    func index(of name: String) -> Int? {
        indices[name]
    }

    /// 見出しの全項目を Shift-JIS で復号します。
    ///
    /// 責務: 項目ごとの復号と、前後の空白の除去を行います。
    /// - Parameter row: 見出し行。
    /// - Returns: 列の順の名前。
    /// - Throws: どれか1つでも復号できなければ `headerNotDecodable`。
    private static func decodedNames(of row: JARTICCSVRow) throws -> [String] {
        try (0..<row.fieldCount).map { index in
            guard let name = String(bytes: row.field(index), encoding: .shiftJIS) else {
                throw JARTICArchiveFormatError.headerNotDecodable
            }
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

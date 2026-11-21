import Foundation
import XCTest
@testable import ProjectZD8

/// アーカイブの読み取りのテストで、170列の見出しと行からなる CSV(Shift-JIS・CR+LF・全項目引用)と、それを入れた ZIP を、
/// テストコードの中で組み立てる補助です。架空の座標だけを使い、実データは使いません。
nonisolated enum JARTICCSVFixture {
    /// 1行の指定です。
    nonisolated struct Row: Sendable {
        /// 共通規制種別コードです(種別ごとの既定値の元)。
        var kind: Int
        /// 既定値に重ねる列の値です(列名ごと)。
        var values: [String: String]
        /// 正なら末尾に項目を足し、負なら末尾の項目を減らします。
        var fieldCountOffset: Int

        /// 責務: 種別と上書きを指定して行を作ります。
        init(kind: Int = 112, _ values: [String: String] = [:], fieldCountOffset: Int = 0) {
            self.kind = kind
            self.values = values
            self.fieldCountOffset = fieldCountOffset
        }
    }

    /// 見本と同じ形の CSV のエントリ名です(基準月 2026-09、版 k_2.1)。
    static let okinawaEntryName = "typeD_okinawa/沖縄県警_202609_k_2.1.csv"
    /// 見本と同じ形のフォルダのエントリ名です。
    static let okinawaFolderName = "typeD_okinawa/"

    /// 責務: 見出しの全列名(必須の列 + 埋め草で170列)を返します。
    static var columnNames: [String] {
        TestJARTICRegulationRowBuilder.columnNames
    }

    /// 責務: 見出しと行から、CSV のバイト列(Shift-JIS・CR+LF・全項目引用)を作ります。
    /// - Parameters:
    ///   - rows: 行の指定。
    ///   - header: 見出しの列名(既定は170列)。
    static func csv(_ rows: [Row], header: [String] = columnNames) -> [UInt8] {
        var bytes = encodeLine(header)
        for row in rows {
            bytes += encodeLine(fields(of: row))
        }
        return bytes
    }

    /// 責務: 1行の項目の値を、見出しの順に並べます。
    static func fields(of row: Row) -> [String] {
        let values = TestJARTICRegulationRowBuilder.baseValues(kind: row.kind).merging(row.values) { _, new in new }
        var fields = columnNames.map { values[$0] ?? "" }
        fields[fields.count - 1] = "0"
        if row.fieldCountOffset > 0 { fields += Array(repeating: "0", count: row.fieldCountOffset) }
        if row.fieldCountOffset < 0 { fields.removeLast(-row.fieldCountOffset) }
        return fields
    }

    /// 責務: 項目を全項目引用・カンマ区切り・CR+LF の1行にして Shift-JIS にします。
    static func encodeLine(_ fields: [String]) -> [UInt8] {
        let text = fields.map { "\"\($0)\"" }.joined(separator: ",") + "\r\n"
        guard let data = text.data(using: .shiftJIS) else { preconditionFailure("Shift-JIS に変換できません") }
        return Array(data)
    }

    /// 責務: フォルダのエントリと CSV のエントリ(UTF-8 の名前)を入れた ZIP のバイト列を作ります。
    /// - Parameters:
    ///   - csv: CSV のバイト列。
    ///   - entryName: CSV のエントリ名。
    ///   - compression: 圧縮方式。
    static func archive(csv: [UInt8], entryName: String = okinawaEntryName, compression: TestZipEntrySpec.Compression = .deflate) -> [UInt8] {
        TestZipArchiveBuilder(entries: [.directory(okinawaFolderName), csvEntry(entryName, csv, compression)]).build()
    }

    /// 責務: UTF-8 の印つきの CSV のエントリを作ります。
    static func csvEntry(_ name: String, _ csv: [UInt8], _ compression: TestZipEntrySpec.Compression = .deflate) -> TestZipEntrySpec {
        var spec = TestZipEntrySpec.file(name, csv, compression)
        spec.usesUTF8Flag = true
        return spec
    }

    /// 責務: 一意なユニークキーを持つ、有効な最高速度(区間)の行を `count` 件作ります。
    static func speedLimitRows(count: Int, keyPrefix: String = "BULK") -> [Row] {
        (0..<count).map { Row(kind: 112, [JARTICColumnName.uniqueKey: "\(keyPrefix)\($0)"]) }
    }
}

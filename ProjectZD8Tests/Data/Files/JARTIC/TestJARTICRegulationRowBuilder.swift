import Foundation
import XCTest
@testable import ProjectZD8

/// 交通規制の CSV の1行の解釈のテストで、170列の見出しと1行を、テストコードの中で組み立てる補助です。架空の座標だけを使います。
nonisolated enum TestJARTICRegulationRowBuilder {
    /// 必須の103列に足す埋め草の列数です(実データと同じ170列にする)。
    static let paddingColumnCount = 67

    /// 線の既定の座標(経度 緯度;経度 緯度)です。
    static let defaultLine = "127.5 26.2;127.6 26.3"
    /// 点の既定の座標です。
    static let defaultPoint = "127.5 26.2"
    /// 面の既定の座標(閉じていない矩形)です。
    static let defaultArea = "127.5 26.2;127.6 26.2;127.6 26.3;127.5 26.3"
    /// 一時停止の既定の進入方向の座標です。
    static let defaultApproach = "127.5 26.3"

    /// 責務: 見出しの全列名(必須の列 + 埋め草)を返します。
    static var columnNames: [String] {
        JARTICColumnName.required + (0..<paddingColumnCount).map { "予備列\($0)" }
    }

    /// 責務: 見出し行を Shift-JIS にして区切り器を通し、見出しを作ります。
    static func header() throws -> JARTICCSVHeader {
        try JARTICCSVHeader(row: try tokenize(columnNames))
    }

    /// 責務: 見出しから行の解釈器を作ります。
    static func parser() throws -> JARTICRegulationRowParser {
        JARTICRegulationRowParser(header: try header())
    }

    /// 責務: 種別ごとに、有効な行になる最小限の列の値を返します。
    static func baseValues(kind: Int) -> [String: String] {
        var values: [String: String] = [
            JARTICColumnName.formatVersion: "k_2.1",
            JARTICColumnName.kindCode: String(kind),
            JARTICColumnName.uniqueKey: "KEY0001",
            JARTICColumnName.updateKind: "5",
        ]
        switch kind {
        case 63:
            values[JARTICColumnName.shapeCode] = "1"
            values[JARTICColumnName.coordinates] = defaultPoint
            values[JARTICColumnName.approachCoordinates] = defaultApproach
        case 114:
            values[JARTICColumnName.shapeCode] = "3"
            values[JARTICColumnName.coordinates] = defaultArea
            values[JARTICColumnName.speed] = "40"
        default:
            values[JARTICColumnName.shapeCode] = "2"
            values[JARTICColumnName.coordinates] = defaultLine
            values[JARTICColumnName.speed] = kind == 112 ? "40" : ""
            values[JARTICColumnName.oneWayOrder] = kind == 11 ? "2" : ""
        }
        return values
    }

    /// 責務: 種別の既定値に上書きを重ねた1行を作ります。
    /// - Parameters:
    ///   - overrides: 列名ごとの上書き(空文字で空にできる)。
    ///   - kind: 共通規制種別コード。
    ///   - fieldCountOffset: 正なら末尾に項目を足し、負なら末尾の項目を減らす。
    static func row(_ overrides: [String: String] = [:], kind: Int = 112, fieldCountOffset: Int = 0) throws -> JARTICCSVRow {
        let values = baseValues(kind: kind).merging(overrides) { _, new in new }
        var fields = columnNames.map { values[$0] ?? "" }
        fields[fields.count - 1] = "0"
        if fieldCountOffset > 0 { fields += Array(repeating: "0", count: fieldCountOffset) }
        if fieldCountOffset < 0 { fields.removeLast(-fieldCountOffset) }
        return try tokenize(fields)
    }

    /// 責務: 上書きつきの行を作って解釈し、結果を返します。
    static func parse(_ overrides: [String: String] = [:], kind: Int = 112, fieldCountOffset: Int = 0) throws -> RoadRegulationArchiveRecord {
        try parser().parse(try row(overrides, kind: kind, fieldCountOffset: fieldCountOffset))
    }

    /// 責務: 有効な座標を作ります(引数は日本の範囲の架空の値)。
    static func coordinate(longitude: Double, latitude: Double) -> GeoCoordinate {
        guard let value = GeoCoordinate(latitude: latitude, longitude: longitude) else {
            preconditionFailure("テストの座標が範囲外です")
        }
        return value
    }

    private static func tokenize(_ fields: [String]) throws -> JARTICCSVRow {
        var bytes: [UInt8] = []
        for (index, field) in fields.enumerated() {
            guard let encoded = field.data(using: .shiftJIS) else { preconditionFailure("Shift-JIS に変換できません: \(field)") }
            bytes += (index == 0 ? [] : [0x2C]) + Array(encoded)
        }
        bytes += [0x0D, 0x0A]
        var tokenizer = JARTICCSVTokenizer()
        var rows: [JARTICCSVRow] = []
        try bytes.withUnsafeBytes { try tokenizer.consume($0, emit: { rows.append($0) }) }
        try tokenizer.finish(emit: { rows.append($0) })
        guard let first = rows.first, rows.count == 1 else { throw TokenizeError.notSingleRow(rows.count) }
        return first
    }

    private enum TokenizeError: Error {
        case notSingleRow(Int)
    }
}

import Foundation
@testable import ProjectZD8

/// CSV の区切りのテストで、バイト列を指定の塊に分けて区切り器へ与え、出てきた行を項目ごとのバイト列として集める補助です。
nonisolated enum TestJARTICCSVRun {
    /// 1行ぶんの項目のバイト列です。
    typealias Fields = [[UInt8]]

    /// 責務: 塊の列を順に区切り器へ与え、最後に `finish` して、出た行を集めます。
    /// - Parameters:
    ///   - chunks: 与える塊。
    ///   - maximumRowBytes: 1行の最大長。
    /// - Returns: 行ごとの項目のバイト列。
    static func rows(chunks: [[UInt8]], maximumRowBytes: Int = 4 << 20) throws -> [Fields] {
        var tokenizer = JARTICCSVTokenizer(maximumRowBytes: maximumRowBytes)
        var rows: [Fields] = []
        let collect: (JARTICCSVRow) -> Void = { row in rows.append(fields(of: row)) }
        for chunk in chunks {
            try chunk.withUnsafeBytes { try tokenizer.consume($0, emit: collect) }
        }
        try tokenizer.finish(emit: collect)
        return rows
    }

    /// 責務: 全体を一括で与えて、出た行を集めます。
    static func rows(_ bytes: [UInt8], maximumRowBytes: Int = 4 << 20) throws -> [Fields] {
        try rows(chunks: [bytes], maximumRowBytes: maximumRowBytes)
    }

    /// 責務: 文字列を UTF-8 で一括して与え、項目を文字列にして返します。
    static func strings(_ text: String) throws -> [[String]] {
        try rows(Array(text.utf8)).map { $0.map { String(decoding: $0, as: UTF8.self) } }
    }

    /// 責務: 位置の列で区切った塊に分けて与えます(位置は昇順・範囲内)。
    static func rows(_ bytes: [UInt8], splitAt positions: [Int]) throws -> [Fields] {
        let bounds = [0] + positions + [bytes.count]
        let chunks = zip(bounds, bounds.dropFirst()).map { Array(bytes[$0..<$1]) }
        return try rows(chunks: chunks)
    }

    /// 責務: 1バイトずつの塊に分けて与えます。
    static func rowsByteByByte(_ bytes: [UInt8]) throws -> [Fields] {
        try rows(chunks: bytes.map { [$0] })
    }

    /// 責務: 行の全項目をバイト列として取り出します。
    static func fields(of row: JARTICCSVRow) -> Fields {
        (0..<row.fieldCount).map { Array(row.field($0)) }
    }
}

import Foundation

/// 都道府県コード(JIS X 0401、1 = 北海道 … 47 = 沖縄県)です。
nonisolated struct JapanesePrefectureCode: Hashable, Comparable, Sendable {
    /// 有効なコードの範囲です。
    static let validRange = 1...47

    /// 47都道府県すべてのコード(昇順)です。
    static let all: [JapanesePrefectureCode] = validRange.compactMap(JapanesePrefectureCode.init)

    /// 1...47 のコード値です。
    let rawValue: Int

    /// コード値を検査して都道府県コードを作ります。
    ///
    /// 責務: 1...47 の値だけを受け入れます。
    /// - Parameter rawValue: コード値。
    /// - Returns: 範囲外なら `nil`。
    init?(_ rawValue: Int) {
        guard Self.validRange.contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// 2桁ゼロ埋めの文字列("01"…"47")です。
    var twoDigitText: String {
        rawValue < 10 ? "0\(rawValue)" : "\(rawValue)"
    }

    /// コード値の昇順で比べます。
    ///
    /// 責務: 都道府県コードの並び順を決めます。
    /// - Parameters:
    ///   - lhs: 左辺。
    ///   - rhs: 右辺。
    /// - Returns: 左辺のコード値が小さければ `true`。
    static func < (lhs: JapanesePrefectureCode, rhs: JapanesePrefectureCode) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

import Foundation

/// 交通規制データの基準月(年と月)です。年は 2000...2999、月は 1...12 です。
nonisolated struct RoadRegulationDataMonth: Hashable, Comparable, Sendable {
    /// 有効な年の範囲です。
    static let validYears = 2000...2999
    /// 有効な月の範囲です。
    static let validMonths = 1...12

    /// 西暦年。
    let year: Int
    /// 月(1...12)。
    let month: Int

    /// 年と月を検査して基準月を作ります。
    ///
    /// 責務: 2000...2999 年・1...12 月の組だけを受け入れます。
    /// - Parameters:
    ///   - year: 西暦年。
    ///   - month: 月。
    /// - Returns: 範囲外なら `nil`。
    init?(year: Int, month: Int) {
        guard Self.validYears.contains(year), Self.validMonths.contains(month) else { return nil }
        self.year = year
        self.month = month
    }

    /// "YYYYMM" 形式の6桁の文字列から基準月を作ります。
    ///
    /// 責務: ちょうど6桁の ASCII 数字を年4桁・月2桁として読み、範囲を検査します。
    /// - Parameter yyyymm: 例 "202609"。
    /// - Returns: 形式または範囲が不正なら `nil`。
    init?(yyyymm: String) {
        guard let digits = Self.asciiDigits(yyyymm), digits.count == 6 else { return nil }
        let year = digits[0..<4].reduce(0) { $0 * 10 + $1 }
        let month = digits[4..<6].reduce(0) { $0 * 10 + $1 }
        self.init(year: year, month: month)
    }

    /// 年、次に月の昇順で比べます。
    ///
    /// 責務: 基準月の新旧を決めます。
    /// - Parameters:
    ///   - lhs: 左辺。
    ///   - rhs: 右辺。
    /// - Returns: 左辺が古ければ `true`。
    static func < (lhs: RoadRegulationDataMonth, rhs: RoadRegulationDataMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    /// 文字列を ASCII の数字の列として読みます。
    ///
    /// 責務: '0'〜'9' 以外の文字を含む文字列を拒否します。
    /// - Parameter text: 読む文字列。
    /// - Returns: 各桁の値。数字以外を含めば `nil`。
    private static func asciiDigits(_ text: String) -> [Int]? {
        let zero = UInt8(ascii: "0")
        let digits = text.utf8.map { Int($0) - Int(zero) }
        return digits.allSatisfy { (0...9).contains($0) } ? digits : nil
    }
}

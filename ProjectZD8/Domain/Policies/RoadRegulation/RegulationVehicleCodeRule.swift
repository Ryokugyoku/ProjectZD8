import Foundation

/// JARTIC の対象車両コード(カテゴリ A〜D)が、本人の車に当てはまるかを判定します。
///
/// コードは右から数えた十進の各桁が 0/1 で、1 の桁がその車両の種類を表します(仕様書の共通コード表「対象コード」)。
/// カテゴリ内の桁とカテゴリ同士は「いずれかが当てはまれば当てはまる」(3値の論理和)で組み合わせます。
nonisolated struct RegulationVehicleCodeRule: Sendable {
    /// 1つのコードの最大の桁数。これを超えるコードは解釈できない。
    private static let maximumDigits = 15
    /// A の15桁目(タイヤチェーンを取り付けていない車両)。本人が当てはまるか分からない。
    private static let tireChainDigit = 15
    /// D の15桁目(その他)。対象なら分からない、除外なら当てはまらないとみなす。
    private static let otherDigit = 15
    /// 普通乗用車が当てはまる A の桁(1 車両、2 自動車、3 乗用、4 普乗、5 普通)。
    private static let standardPassengerDigits: Set<Int> = [1, 2, 3, 4, 5]
    /// 軽乗用車でさらに当てはまる A の桁(10 軽)。
    private static let keiDigit = 10
    /// ASCII の `0` のバイト。
    private static let asciiZero = UInt8(ascii: "0")
    /// ASCII の `1` のバイト。
    private static let asciiOne = UInt8(ascii: "1")

    /// カテゴリ A〜D(配列の位置 0〜3)ごとの、当てはまる桁です。
    private let matchingDigits: [Set<Int>]
    /// カテゴリ A〜D ごとの、対象として判定すると分からない桁です。
    private let targetUncertainDigits: [Set<Int>]
    /// カテゴリ A〜D ごとの、除外として判定すると分からない桁です(除外の「その他」は含めない)。
    private let exclusionUncertainDigits: [Set<Int>]

    /// 本人の車の種類から規則を作ります。
    ///
    /// 責務: 車の種類に応じて、カテゴリごとの当てはまる桁と分からない桁の表を用意します。
    /// - Parameter vehicleClass: 本人の車の種類。
    init(vehicleClass: RegulationVehicleClass) {
        let passengerDigits = vehicleClass == .keiPassenger
            ? Self.standardPassengerDigits.union([Self.keiDigit])
            : Self.standardPassengerDigits
        matchingDigits = [passengerDigits, [], [], []]
        targetUncertainDigits = [[Self.tireChainDigit], [], [], [Self.otherDigit]]
        exclusionUncertainDigits = [[Self.tireChainDigit], [], [], []]
    }

    /// 対象の組の車両コードが本人の車に当てはまるかを返します。
    ///
    /// 責務: A〜D のうち値のあるコードを、対象の表で判定して論理和を取ります。
    /// - Parameter set: 対象の1組。
    /// - Returns: A〜D がすべて空なら `applies`(車両の制約なし)。
    func evaluateTarget(_ set: RoadRegulationConditionSet) -> RegulationApplicability {
        evaluate(set, uncertainDigits: targetUncertainDigits)
    }

    /// 除外の組の車両コードが本人の車に当てはまるかを返します。
    ///
    /// 責務: A〜D のうち値のあるコードを、除外の表(D の「その他」は当てはまらない)で判定して論理和を取ります。
    /// - Parameter set: 除外の1組。
    /// - Returns: A〜D がすべて空なら `applies`(車両の制約なし)。
    func evaluateExclusion(_ set: RoadRegulationConditionSet) -> RegulationApplicability {
        evaluate(set, uncertainDigits: exclusionUncertainDigits)
    }

    /// 1組の A〜D のコードを判定します。
    ///
    /// 責務: 値のあるカテゴリだけを判定し、論理和で組み合わせます。
    /// - Parameters:
    ///   - set: 判定する組。
    ///   - uncertainDigits: カテゴリごとの分からない桁。
    /// - Returns: 値のあるカテゴリが無ければ `applies`。
    private func evaluate(_ set: RoadRegulationConditionSet, uncertainDigits: [Set<Int>]) -> RegulationApplicability {
        let codes = [set.vehicleCodeA, set.vehicleCodeB, set.vehicleCodeC, set.vehicleCodeD]
        let results = codes.indices.compactMap { category in
            codes[category].map { evaluateCode($0, matching: matchingDigits[category], uncertain: uncertainDigits[category]) }
        }
        guard let first = results.first else { return .applies }
        return results.dropFirst().reduce(first) { $0.or($1) }
    }

    /// 1つのカテゴリのコードを判定します。
    ///
    /// 責務: 立っている桁ごとに表で3値を引き、論理和を取ります。
    /// - Parameters:
    ///   - code: コードの文字列。
    ///   - matching: 当てはまる桁。
    ///   - uncertain: 分からない桁。
    /// - Returns: 0/1 以外の文字を含む、または16桁以上なら `unknown`。立っている桁が無ければ `doesNotApply`。
    private func evaluateCode(_ code: String, matching: Set<Int>, uncertain: Set<Int>) -> RegulationApplicability {
        guard let digits = Self.setDigits(of: code) else { return .unknown }
        return digits.reduce(RegulationApplicability.doesNotApply) { result, digit in
            if matching.contains(digit) { return result.or(.applies) }
            return uncertain.contains(digit) ? result.or(.unknown) : result
        }
    }

    /// コードの中で 1 が立っている桁の位置(右から 1 始まり)を返します。
    ///
    /// 責務: 0/1 だけからなる15桁以下のコードを受け付け、1 の桁を集めます。
    /// - Parameter code: コードの文字列。
    /// - Returns: 1 の桁の位置。解釈できなければ `nil`。
    private static func setDigits(of code: String) -> [Int]? {
        let bytes = Array(code.utf8)
        guard bytes.count <= maximumDigits, bytes.allSatisfy({ $0 == asciiZero || $0 == asciiOne }) else { return nil }
        return bytes.reversed().enumerated().compactMap { offset, byte in byte == asciiOne ? offset + 1 : nil }
    }
}

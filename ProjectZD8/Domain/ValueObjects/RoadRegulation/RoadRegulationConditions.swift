import Foundation

/// 規制の対象1〜5と除外1〜5の条件です。どちらも常に5件で、index 0 が対象1(除外1)です。
nonisolated struct RoadRegulationConditions: Codable, Equatable, Sendable {
    /// 対象・除外それぞれの組の数です。
    static let setCount = 5

    /// 対象も除外も持たない(常に適用する)条件です。
    static let unconditional = RoadRegulationConditions(targets: [], exclusions: [])

    /// 対象1〜5(常に5件)。
    let targets: [RoadRegulationConditionSet]
    /// 除外1〜5(常に5件)。
    let exclusions: [RoadRegulationConditionSet]

    /// 対象と除外の組から条件を作ります。
    ///
    /// 責務: どちらも5件に揃えます(足りなければ空の組で埋め、多ければ切ります)。
    /// - Parameters:
    ///   - targets: 対象の組(先頭が対象1)。
    ///   - exclusions: 除外の組(先頭が除外1)。
    init(targets: [RoadRegulationConditionSet], exclusions: [RoadRegulationConditionSet]) {
        self.targets = Self.fittedToSetCount(targets)
        self.exclusions = Self.fittedToSetCount(exclusions)
    }

    /// 保存済みの JSON から条件を復元します。
    ///
    /// 責務: 復元した組も5件に揃え、件数の不変条件を保ちます。
    /// - Parameter decoder: 復元元。
    /// - Throws: 形式が合わなければ復元のエラー。
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            targets: try container.decode([RoadRegulationConditionSet].self, forKey: .targets),
            exclusions: try container.decode([RoadRegulationConditionSet].self, forKey: .exclusions)
        )
    }

    /// 対象も除外もすべて空かどうかです。
    var isUnconditional: Bool {
        targets.allSatisfy(\.isEmpty) && exclusions.allSatisfy(\.isEmpty)
    }

    /// 保存する項目のキーです。
    private enum CodingKeys: String, CodingKey {
        case targets
        case exclusions
    }

    /// 組の列を5件に揃えます。
    ///
    /// 責務: 5件を超える分を切り、足りない分を空の組で埋めます。
    /// - Parameter sets: 元の組の列。
    /// - Returns: ちょうど5件の組の列。
    private static func fittedToSetCount(_ sets: [RoadRegulationConditionSet]) -> [RoadRegulationConditionSet] {
        let kept = Array(sets.prefix(setCount))
        return kept + Array(repeating: .empty, count: setCount - kept.count)
    }
}

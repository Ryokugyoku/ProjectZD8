import Foundation
@testable import ProjectZD8

/// 経路のテストで、規制の行 ID ごとに条件の判定を決めた関数を作る補助です(表に無い規制は `applies`)。
nonisolated enum RoadRegulationApplicabilityTable {
    /// 責務: 行 ID → 条件の判定の表から、経路へ渡す判定の関数を作ります。
    /// - Parameter values: 行 ID → 条件の判定。
    /// - Returns: 表に無い規制には `applies` を返す関数。
    static func closure(_ values: [Int64: RegulationApplicability]) -> (RoadRegulation, Date) -> RegulationApplicability {
        { regulation, _ in values[regulation.id.rawValue] ?? .applies }
    }

    /// 責務: 実物の条件の評価器(普通乗用車)を使う判定の関数を作ります。
    /// - Returns: 規制の条件を点の時刻で評価する関数。
    static func realEvaluator() -> (RoadRegulation, Date) -> RegulationApplicability {
        let evaluator = RoadRegulationApplicabilityEvaluator()
        return { regulation, date in evaluator.evaluate(regulation.conditions, at: date) }
    }
}

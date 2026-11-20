import Foundation

/// 保存済みの交通規制1件を識別します(DB の行 ID)。
nonisolated struct RoadRegulationID: Hashable, Comparable, Sendable {
    /// DB が採番した行 ID です。
    let rawValue: Int64

    /// 行 ID の昇順で比べます。
    ///
    /// 責務: 規制の安定した並び順を決めます。
    /// - Parameters:
    ///   - lhs: 左辺。
    ///   - rhs: 右辺。
    /// - Returns: 左辺の行 ID が小さければ `true`。
    static func < (lhs: RoadRegulationID, rhs: RoadRegulationID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

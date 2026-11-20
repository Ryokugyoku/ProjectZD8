import Foundation

/// 取り込みで CSV の行を捨てた理由です。`rawValue` は DB の CHECK 制約に固定されています。
nonisolated enum RoadRegulationRowRejection: String, CaseIterable, Codable, Sendable {
    /// 項目数が見出しと違う。
    case fieldCountMismatch
    /// 必須項目が欠けている。
    case missingRequiredField
    /// 点・線・面コードが種別と合わない。
    case shapeMismatch
    /// 座標が読めない、または日本の範囲外。
    case invalidCoordinates
    /// 形状として成り立たない(点数不足など)。
    case invalidGeometry
    /// 一時停止の進入方向の座標が無い。
    case missingApproachCoordinates
    /// 最高速度の値が不正。
    case invalidSpeed
    /// 一方通行の指定・禁止方向の別コードが不正。
    case invalidOneWayOrder
    /// 形状が覆う升目が上限を超える。
    case geometryTooLarge
    /// 同じ版にユニークキーが既にある。
    case duplicateUniqueKey
}

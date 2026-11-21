import Foundation

/// 1件の判定に添える数値です。文言を持たず、該当しない項目は `nil` です。
nonisolated struct SessionRoadRegulationReviewFigures: Equatable, Sendable {
    /// 最高速度の制限値(km/h)です。
    var limitKph: Int? = nil
    /// 区間の最高車速(km/h)です。
    var maximumKph: Double? = nil
    /// 停止線までの最低車速(km/h)です。
    var minimumKph: Double? = nil
    /// 制限を超えていた秒数です。
    var exceededSeconds: Double? = nil
    /// 指定と逆の向きに進んだ距離(m)です。
    var wrongWayDistanceMeters: Double? = nil
    /// 徐行の目安の車速(km/h)です。
    var referenceKph: Double? = nil
}

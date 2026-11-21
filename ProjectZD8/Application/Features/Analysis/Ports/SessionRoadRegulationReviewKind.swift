import Foundation

/// 照合する交通規制の種類です。宣言の順が表示の順です。
nonisolated enum SessionRoadRegulationReviewKind: String, CaseIterable, Sendable {
    /// 最高速度です。
    case speedLimit
    /// 一時停止です。
    case stop
    /// 一方通行です。
    case oneWay
    /// 徐行です。
    case slowDown
}

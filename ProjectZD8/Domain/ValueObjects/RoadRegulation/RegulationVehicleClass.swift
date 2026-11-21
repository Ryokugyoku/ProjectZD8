import Foundation

/// 条件の判定で本人の車とみなす車両の種類です。
nonisolated enum RegulationVehicleClass: String, Sendable {
    /// 普通乗用車(軽でない)。既定。
    case standardPassenger
    /// 軽乗用車。
    case keiPassenger
}

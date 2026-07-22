import Foundation

/// 登録車両の識別値をZD8型式へ安全に照合します。
struct ZD8VehicleModelPolicy {
    /// 専用PID表示に使用する型式文字列です。
    static let modelCode = "ZD8"

    /// 国内型式または確認済み海外VIN接頭辞をZD8へ照合します。
    ///
    /// 責務: 1件の車両識別文字列をZD8型式の適用可否へ変換します。
    /// - Parameter identifier: VINまたはOBD由来の車両識別文字列。
    /// - Returns: `ZD8` または `JF1ZD` で始まる場合は `true`。
    func matches(_ identifier: String?) -> Bool {
        guard let normalized = identifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
              !normalized.isEmpty else { return false }
        return normalized.hasPrefix(Self.modelCode) || normalized.hasPrefix("JF1ZD")
    }

    /// 車両プロフィールがZD8専用PIDの適用対象か判定します。
    ///
    /// 責務: 1台の登録車両が持つVINとOBD識別子をZD8型式へ照合します。
    /// - Parameter vehicle: 判定する登録車両プロフィール。
    /// - Returns: いずれかの識別値がZD8を示す場合は `true`。
    func matches(_ vehicle: VehicleProfile) -> Bool {
        matches(vehicle.vin) || matches(vehicle.obdIdentifier)
    }
}

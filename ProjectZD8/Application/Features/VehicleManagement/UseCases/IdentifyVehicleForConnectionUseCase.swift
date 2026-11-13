import Foundation

/// OBD識別結果を登録済み車両または新規登録候補へ振り分けます。
struct IdentifyVehicleForConnectionUseCase {
    /// 車両識別子の照合結果としてApplicationへ返す分岐です。
    enum Outcome: Equatable {
        /// 同種の識別子が一致した登録済み車両です。
        case registered(VehicleProfile, VehicleIdentificationSnapshot)
        /// 未登録の車両識別子を含む確認対象観測です。
        case requiresRegistration(VehicleIdentificationSnapshot)
    }

    /// 実OBD識別を行う注入済み境界です。
    private let identification: any VehicleIdentificationPort

    /// OBD識別境界を注入して生成します。
    ///
    /// 責務: 車両識別取得能力を同種識別子照合ユースケースへ固定します。
    /// - Parameter identification: OBDから識別観測を取得する境界。
    init(identification: any VehicleIdentificationPort) {
        self.identification = identification
    }

    /// OBD観測のVINまたは非VIN識別子を現在の登録車両へ照合します。
    ///
    /// 責務: 1回の識別観測を登録済み接続または新規登録確認へ振り分けます。
    /// - Parameters:
    ///   - endpoint: 接続するOBDアダプターの物理終端。
    ///   - vehicles: 現在のアカウントに属する登録車両。
    /// - Returns: 登録済み車両または未登録観測。
    func execute(endpoint: OBDConnectionEndpoint, vehicles: [VehicleProfile]) async throws -> Outcome {
        let snapshot = try await identification.identifyVehicle(using: endpoint)
        let vin = snapshot.vin?.trimmingCharacters(in: .whitespacesAndNewlines)
        let obdIdentifier = snapshot.obdIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard vin?.isEmpty == false || obdIdentifier?.isEmpty == false else {
            throw VehicleIdentificationError.vinUnavailable
        }
        if let registered = vehicles.first(where: { vehicle in
            if let vin, !vin.isEmpty {
                return !vehicle.vin.isEmpty && vehicle.vin.caseInsensitiveCompare(vin) == .orderedSame
            }
            guard let obdIdentifier, let registeredIdentifier = vehicle.obdIdentifier else { return false }
            return registeredIdentifier.caseInsensitiveCompare(obdIdentifier) == .orderedSame
        }) {
            return .registered(registered, snapshot)
        }
        return .requiresRegistration(snapshot)
    }
}

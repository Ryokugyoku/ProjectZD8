import Foundation
@testable import ProjectZD8

/// 固定の保存済みcapabilityを返す車両別capability Repositoryです。
struct StubVehiclePIDCapabilityRepository: VehiclePIDCapabilityRepository {
    /// 返すcapabilityです。
    private let storedCapabilities: [VehiclePIDCapability]

    /// 返すcapabilityを固定します。
    ///
    /// 責務: 初回探索を起こさない保存済みcapabilityを持つRepositoryを構築します。
    /// - Parameter capabilities: 返すcapability。
    init(capabilities: [VehiclePIDCapability]) {
        storedCapabilities = capabilities
    }

    /// 定義に対応するテスト車両のcapabilityを生成します。
    ///
    /// 責務: 収集トグルだけを差し替えたcapabilityを返します。
    /// - Parameters:
    ///   - definition: 対応するPID定義。
    ///   - enabled: 収集トグル。
    /// - Returns: テスト車両のcapability。
    static func capability(_ definition: OBDPIDDefinition, enabled: Bool) -> VehiclePIDCapability {
        VehiclePIDCapability(
            vehicleID: LiveTelemetryTestDefinitions.vehicleID,
            request: LiveTelemetryTestDefinitions.request(definition),
            isCollectionEnabled: enabled,
            discoveredAt: Date(timeIntervalSince1970: 1)
        )
    }

    /// 固定のcapabilityを返します。
    ///
    /// 責務: 車両IDにかかわらず固定のcapabilityを返します。
    /// - Parameter vehicleID: 参照する車両ID。
    /// - Returns: 固定のcapability。
    func capabilities(for vehicleID: VehicleID) throws -> [VehiclePIDCapability] {
        storedCapabilities
    }

    /// 初回保存を受け付けます。
    ///
    /// 責務: テストで使わない保存を変更なしで完了します。
    /// - Parameters:
    ///   - capabilities: 使わないcapability。
    ///   - vehicleID: 使わない車両ID。
    func insertInitial(_ capabilities: [VehiclePIDCapability], for vehicleID: VehicleID) throws {}

    /// 追加保存を受け付けます。
    ///
    /// 責務: テストで使わない保存を変更なしで完了します。
    /// - Parameters:
    ///   - capabilities: 使わないcapability。
    ///   - vehicleID: 使わない車両ID。
    func mergeDiscovered(_ capabilities: [VehiclePIDCapability], for vehicleID: VehicleID) throws {}

    /// 収集トグルの変更を受け付けます。
    ///
    /// 責務: テストで使わない変更を変更なしで完了します。
    /// - Parameters:
    ///   - isEnabled: 使わない収集トグル。
    ///   - request: 使わない要求。
    ///   - vehicleID: 使わない車両ID。
    func setCollectionEnabled(_ isEnabled: Bool, for request: OBDPIDRequest, vehicleID: VehicleID) throws {}
}

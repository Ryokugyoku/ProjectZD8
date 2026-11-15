import Foundation

/// 車両別の保存済み対応PIDを再利用し、未収集時だけService 01ビットマップを探索します。
struct LoadVehiclePIDCapabilitiesUseCase: Sendable {
    /// 車両別対応PIDの永続化境界です。
    private let repository: any VehiclePIDCapabilityRepository
    /// 標準PIDと車種専用PIDをアダプターへ問い合わせる探索処理です。
    private let discovery: DiscoverSupportedOBDPIDsUseCase
    /// 対応確認日時を供給するクロックです。
    private let now: @Sendable () -> Date

    /// 永続化、通信、時刻境界を固定します。
    ///
    /// 責務: 車両別対応PIDの再利用または初回探索に必要な境界を保持します。
    /// - Parameters:
    ///   - repository: 車両別対応PID保存先。
    ///   - telemetry: 対応ビットマップ読取境界。
    ///   - definitionRepository: 車種専用PID定義の読込先。
    ///   - now: 対応確認日時の供給元。
    init(
        repository: any VehiclePIDCapabilityRepository,
        telemetry: any OBDPIDTelemetryPort,
        definitionRepository: (any OBDPIDDefinitionRepository)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        discovery = DiscoverSupportedOBDPIDsUseCase(
            telemetry: telemetry,
            definitionRepository: definitionRepository
        )
        self.now = now
    }

    /// 保存済み設定を返し、0件の場合だけ00から連鎖する0x20刻みの範囲を探索します。
    ///
    /// 責務: 1台の車両を収集選択付き対応PID一覧へ変換します。
    /// - Parameters:
    ///   - vehicleID: 対応PIDを取得するアプリ内車両ID。
    ///   - vehicleModelCode: 車種専用PID探索を許可する確認済み型式。
    ///   - endpoint: 未収集時に探索へ使用するOBD終端。
    /// - Returns: 保存済みまたは新規登録した対応PID設定。
    /// - Throws: 永続化、通信、またはビットマップ応答が不正な場合のエラー。
    func execute(
        vehicleID: VehicleID,
        vehicleModelCode: String? = nil,
        endpoint: OBDConnectionEndpoint
    ) async throws -> [VehiclePIDCapability] {
        let stored = try repository.capabilities(for: vehicleID)
        var capabilities = stored
        if stored.isEmpty {
            let requests = try await discovery.discoverStandard(using: endpoint)
            let discoveredAt = now()
            capabilities = requests.map {
                VehiclePIDCapability(vehicleID: vehicleID, request: $0, isCollectionEnabled: true, discoveredAt: discoveredAt)
            }
            try repository.insertInitial(capabilities, for: vehicleID)
        }
        let added = try await discoverVehicleSpecific(
            vehicleID: vehicleID,
            vehicleModelCode: vehicleModelCode,
            excluding: Set(capabilities.map(\.id.request)),
            endpoint: endpoint
        )
        if !added.isEmpty {
            try repository.mergeDiscovered(added, for: vehicleID)
            capabilities.append(contentsOf: added)
        }
        return capabilities.sorted { ($0.id.request.service, $0.id.request.pid) < ($1.id.request.service, $1.id.request.pid) }
    }

    /// 型式一致する専用PIDを個別送信し、応答済みだけを対応登録候補にします。
    ///
    /// 責務: 1台の型式一致車両を応答確認済み専用PID設定へ変換します。
    /// - Parameters:
    ///   - vehicleID: 登録先の車両ID。
    ///   - vehicleModelCode: 接続前識別で確認した型式。
    ///   - excluding: 既に登録済みのService/PID。
    ///   - endpoint: 探索へ使用するOBD終端。
    /// - Returns: 今回初めて正応答を確認できた専用PID設定。
    /// - Throws: 定義読込または通信境界に失敗した場合のエラー。
    private func discoverVehicleSpecific(
        vehicleID: VehicleID,
        vehicleModelCode: String?,
        excluding: Set<OBDPIDRequest>,
        endpoint: OBDConnectionEndpoint
    ) async throws -> [VehiclePIDCapability] {
        let requests = try await discovery.discoverVehicleSpecific(
            vehicleModelCode: vehicleModelCode,
            excluding: excluding,
            endpoint: endpoint
        )
        guard !requests.isEmpty else { return [] }
        let discoveredAt = now()
        return requests.map {
            VehiclePIDCapability(vehicleID: vehicleID, request: $0, isCollectionEnabled: true, discoveredAt: discoveredAt)
        }
    }
}

import Foundation

/// 車両別の保存済み対応PIDを再利用し、未収集時だけService 01ビットマップを探索します。
struct LoadVehiclePIDCapabilitiesUseCase: Sendable {
    /// 車両別対応PIDの永続化境界です。
    private let repository: any VehiclePIDCapabilityRepository
    /// Service 01対応ビットマップを読み取る通信境界です。
    private let telemetry: any OBDPIDTelemetryPort
    /// 車種専用定義を取得するPIDカタログ境界です。
    private let definitionRepository: (any OBDPIDDefinitionRepository)?
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
        self.telemetry = telemetry
        self.definitionRepository = definitionRepository
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
            let requests = try await discover(using: endpoint)
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
        guard let vehicleModelCode, let definitionRepository else { return [] }
        let definitions = try definitionRepository.definitions().filter {
            $0.vehicleModelCode?.caseInsensitiveCompare(vehicleModelCode) == .orderedSame
                && !excluding.contains(OBDPIDRequest(service: $0.service, pid: $0.pid))
        }
        guard !definitions.isEmpty else { return [] }
        let responses = try await telemetry.readVehicleSpecific(definitions, using: endpoint)
        let discoveredAt = now()
        return definitions.compactMap { definition in
            let request = OBDPIDRequest(service: definition.service, pid: definition.pid)
            guard responses[request] != nil else { return nil }
            return VehiclePIDCapability(
                vehicleID: vehicleID,
                request: request,
                isCollectionEnabled: true,
                discoveredAt: discoveredAt
            )
        }
    }

    /// Service 01の対応範囲ビットマップを継続ビットに従って読み取ります。
    ///
    /// 責務: 00からE0までの0x20刻み照会連鎖を対応データPID集合へ変換します。
    /// - Parameter endpoint: 探索へ使用するOBD終端。
    /// - Returns: 対応が通知されたデータPIDの昇順一覧。
    /// - Throws: 通信失敗または4バイト未満の応答の場合のエラー。
    private func discover(using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest] {
        var supported: [OBDPIDRequest] = []
        var base: UInt8 = 0x00
        while base <= 0xE0 {
            let query = OBDPIDRequest(service: 0x01, pid: base)
            let response = try await telemetry.read([query], using: endpoint)
            guard let bytes = response[query], bytes.count >= 4 else {
                throw OBDPIDTelemetryError.noVehicleResponse
            }
            for offset in 1...32 where bitIsSet(offset: offset, bytes: bytes) {
                let value = Int(base) + offset
                guard value <= 0xFF, value % 0x20 != 0 else { continue }
                supported.append(OBDPIDRequest(service: 0x01, pid: UInt8(value)))
            }
            guard bitIsSet(offset: 32, bytes: bytes), base < 0xE0 else { break }
            base &+= 0x20
        }
        return supported
    }

    /// 4バイト対応ビットマップ内のPID位置を判定します。
    ///
    /// 責務: 1始まりのPIDオフセットをbig-endianビットマップの真偽へ変換します。
    /// - Parameters:
    ///   - offset: 1から32のPIDオフセット。
    ///   - bytes: 対応ビットマップ先頭4バイト。
    /// - Returns: 対応ビットが立っている場合は `true`。
    private func bitIsSet(offset: Int, bytes: [UInt8]) -> Bool {
        let zeroBased = offset - 1
        return bytes[zeroBased / 8] & (0x80 >> UInt8(zeroBased % 8)) != 0
    }
}

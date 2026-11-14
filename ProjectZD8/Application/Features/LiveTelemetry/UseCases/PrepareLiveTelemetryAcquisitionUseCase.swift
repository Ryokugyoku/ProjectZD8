/// 取得開始前に、車両の登録状態に応じて取得対象のPID定義とcapabilityを確定します。
///
/// 登録済み車両: 車両別の収集トグル(`isCollectionEnabled`)が切られたPIDは
/// `ReadMajorOBDPIDsUseCase.loadDefinitions(for:)` で取り除かれ、取得ループの対象に入りません。
/// 未登録車両: 対応PIDビットマップでECUが対応を返した標準PIDだけを、すべて収集対象とします。車種専用PIDは要求しません。
struct PrepareLiveTelemetryAcquisitionUseCase {
    /// 数値化可能なPID定義を読み込むユースケースです。
    private let readMajorPIDs: ReadMajorOBDPIDsUseCase
    /// 車両別の対応PIDを再利用または初回探索するユースケースです。未設定なら登録済み車両でPIDカタログ全体を使います。
    private let loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase?
    /// 未登録車両でECUが対応を返した標準PIDを求めるユースケースです。
    private let discoverSupportedStandardPIDs: DiscoverSupportedStandardPIDsUseCase

    /// 定義読込、車両別capability読込、対応PID探索のユースケースを固定します。
    ///
    /// 責務: 取得対象の確定に使うユースケースを注入します。
    /// - Parameters:
    ///   - readMajorPIDs: 数値化可能なPID定義を読み込むユースケース。
    ///   - loadVehicleCapabilities: 車両別の対応PIDを再利用または初回探索するユースケース。
    ///   - discoverSupportedStandardPIDs: 未登録車両でECUが対応を返した標準PIDを求めるユースケース。
    init(
        readMajorPIDs: ReadMajorOBDPIDsUseCase,
        loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase?,
        discoverSupportedStandardPIDs: DiscoverSupportedStandardPIDsUseCase
    ) {
        self.readMajorPIDs = readMajorPIDs
        self.loadVehicleCapabilities = loadVehicleCapabilities
        self.discoverSupportedStandardPIDs = discoverSupportedStandardPIDs
    }

    /// 取得対象のPID定義とcapabilityを確定します。
    ///
    /// 責務: 車両の登録状態を、収集対象の数値化可能定義とその確認済みcapabilityへ変換します。
    /// - Parameters:
    ///   - vehicle: 登録済み車両(ID・型式コード)または未登録。
    ///   - endpoint: 対応PIDの探索に使うOBD終端。
    /// - Returns: 取得対象定義と、定義ごとのcapability(登録済みで車両別設定を使わない場合は空)。
    /// - Throws: PIDカタログ・capabilityの読込失敗、対応PIDの探索失敗、または収集対象が空の場合のエラー。
    func execute(
        vehicle: LiveTelemetryVehicleContext,
        endpoint: OBDConnectionEndpoint
    ) async throws -> (definitions: [OBDPIDDefinition], capabilities: [ConnectionSessionAcquisitionPIDCapabilityInput]) {
        switch vehicle {
        case let .registered(vehicleID, vehicleModelCode):
            return try await prepareRegistered(vehicleID: vehicleID, vehicleModelCode: vehicleModelCode, endpoint: endpoint)
        case .unregistered:
            return try await prepareUnregistered(endpoint: endpoint)
        }
    }

    /// 登録済み車両の取得対象を確定します。
    ///
    /// 責務: 車両の対応PIDと収集トグルを、収集有効な数値化可能定義とその確認済みcapabilityへ変換します。
    /// - Parameters:
    ///   - vehicleID: 対応PID設定を参照する車両ID。
    ///   - vehicleModelCode: 確認済み車種専用PIDを適用する型式コード。
    ///   - endpoint: 初回探索に使うOBD終端。
    /// - Returns: 取得対象定義と、車両別capabilityを使う場合の定義ごとのcapability。
    /// - Throws: PIDカタログ・capabilityの読込失敗、または収集対象が空の場合のエラー。
    private func prepareRegistered(
        vehicleID: VehicleID,
        vehicleModelCode: String?,
        endpoint: OBDConnectionEndpoint
    ) async throws -> (definitions: [OBDPIDDefinition], capabilities: [ConnectionSessionAcquisitionPIDCapabilityInput]) {
        guard let loadVehicleCapabilities else { return (try readMajorPIDs.loadDefinitions(), []) }
        let capabilities = try await loadVehicleCapabilities.execute(
            vehicleID: vehicleID,
            vehicleModelCode: vehicleModelCode,
            endpoint: endpoint
        )
        let definitions = try readMajorPIDs.loadDefinitions(for: capabilities)
        let capabilityByRequest = Dictionary(
            capabilities.map { ($0.id.request, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let inputs = definitions.compactMap { definition -> ConnectionSessionAcquisitionPIDCapabilityInput? in
            let request = OBDPIDRequest(service: definition.service, pid: definition.pid)
            guard let capability = capabilityByRequest[request], capability.isCollectionEnabled else { return nil }
            return ConnectionSessionAcquisitionPIDCapabilityInput(
                request: request,
                support: .supported,
                isCollectionEnabled: capability.isCollectionEnabled
            )
        }
        return (definitions, inputs)
    }

    /// 未登録車両の取得対象を確定します。
    ///
    /// 責務: 対応PIDビットマップでECUが対応を返した標準PIDの定義と、未登録車両用のcapability証跡を返します。
    /// 車両別設定を保存しないため、探索結果は永続化しません。
    /// - Parameter endpoint: 対応PIDの探索に使うOBD終端。
    /// - Returns: 取得対象定義と、定義ごとの未登録車両用capability。
    /// - Throws: 対応PIDの探索失敗、PIDカタログの読込失敗、または対象が空の場合のエラー。
    private func prepareUnregistered(
        endpoint: OBDConnectionEndpoint
    ) async throws -> (definitions: [OBDPIDDefinition], capabilities: [ConnectionSessionAcquisitionPIDCapabilityInput]) {
        let supported = try await discoverSupportedStandardPIDs.execute(using: endpoint)
        let definitions = try readMajorPIDs.loadStandardDefinitions(supported: supported)
        let inputs = definitions.map {
            ConnectionSessionAcquisitionPIDCapabilityInput.unregisteredVehicleSupported(
                OBDPIDRequest(service: $0.service, pid: $0.pid)
            )
        }
        return (definitions, inputs)
    }

    /// PID取得境界が保持する接続資源を解放します。
    ///
    /// 責務: 取得を始められなかった場合に初回探索で開いた接続を閉じます。
    func endSession() async {
        await readMajorPIDs.endSession()
    }
}

/// 取得開始前に、車両の収集設定から取得対象のPID定義とcapabilityを確定します。
///
/// 車両別の収集トグル(`isCollectionEnabled`)が切られたPIDは
/// `ReadMajorOBDPIDsUseCase.loadDefinitions(for:)` で取り除かれ、取得ループの対象に入りません。
struct PrepareLiveTelemetryAcquisitionUseCase {
    /// 数値化可能なPID定義を読み込むユースケースです。
    private let readMajorPIDs: ReadMajorOBDPIDsUseCase
    /// 車両別の対応PIDを再利用または初回探索するユースケースです。未設定ならPIDカタログ全体を使います。
    private let loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase?

    /// 定義読込と車両別capability読込のユースケースを固定します。
    ///
    /// 責務: 取得対象の確定に使うユースケースを注入します。
    /// - Parameters:
    ///   - readMajorPIDs: 数値化可能なPID定義を読み込むユースケース。
    ///   - loadVehicleCapabilities: 車両別の対応PIDを再利用または初回探索するユースケース。
    init(readMajorPIDs: ReadMajorOBDPIDsUseCase, loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase?) {
        self.readMajorPIDs = readMajorPIDs
        self.loadVehicleCapabilities = loadVehicleCapabilities
    }

    /// 取得対象のPID定義とcapabilityを確定します。
    ///
    /// 責務: 車両の対応PIDと収集トグルを、収集有効な数値化可能定義とその確認済みcapabilityへ変換します。
    /// - Parameters:
    ///   - vehicleID: 対応PID設定を参照する車両ID。
    ///   - vehicleModelCode: 確認済み車種専用PIDを適用する型式コード。
    ///   - endpoint: 初回探索に使うOBD終端。
    /// - Returns: 取得対象定義と、車両別capabilityを使う場合の定義ごとのcapability。
    /// - Throws: PIDカタログ・capabilityの読込失敗、または収集対象が空の場合のエラー。
    func execute(
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

    /// PID取得境界が保持する接続資源を解放します。
    ///
    /// 責務: 取得を始められなかった場合に初回探索で開いた接続を閉じます。
    func endSession() async {
        await readMajorPIDs.endSession()
    }
}

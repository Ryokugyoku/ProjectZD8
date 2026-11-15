/// 開始要求の車両有無に応じて、継続取得で照会するPID定義と対応状況を決定します。
///
/// 車両ありの場合は車両単位で保存した対応PIDを使い、車両なしの場合は保存を伴わずアダプターへ毎回問い合わせます。
struct ResolveLiveTelemetryAcquisitionTargetsUseCase {
    /// PIDカタログから数値化可能定義を読み込むユースケースです。
    private let readMajorPIDs: ReadMajorOBDPIDsUseCase
    /// 車両別の対応PIDを再利用または初回探索するユースケースです。
    private let loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase?
    /// 車両未登録時に保存を伴わず対応PIDを探索するユースケースです。
    private let discoverSupportedPIDs: DiscoverSupportedOBDPIDsUseCase?

    /// 定義読込、車両別対応PID、保存なし探索の各ユースケースを固定します。
    ///
    /// 責務: 取得対象PIDの決定に必要なユースケースを保持します。
    /// - Parameters:
    ///   - readMajorPIDs: PIDカタログから数値化可能定義を読み込むユースケース。
    ///   - loadVehicleCapabilities: 車両別の対応PIDを再利用または初回探索するユースケース。
    ///   - discoverSupportedPIDs: 車両未登録時に保存を伴わず対応PIDを探索するユースケース。
    init(
        readMajorPIDs: ReadMajorOBDPIDsUseCase,
        loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase?,
        discoverSupportedPIDs: DiscoverSupportedOBDPIDsUseCase?
    ) {
        self.readMajorPIDs = readMajorPIDs
        self.loadVehicleCapabilities = loadVehicleCapabilities
        self.discoverSupportedPIDs = discoverSupportedPIDs
    }

    /// 開始要求を取得対象PID定義と対応状況へ変換します。
    ///
    /// 責務: 車両有無に応じた1つの対応PID決定経路を選び、取得対象を確定します。
    /// - Parameter request: 終端、車両、型式を含む開始要求。
    /// - Returns: 取得対象PID定義と、定義ごとの対応状況。
    /// - Throws: 車両なしで探索ユースケースが無い場合は `OBDPIDTelemetryError.unavailable`、
    ///   探索・永続化・カタログ読込に失敗した場合はそのエラー。
    func execute(_ request: LiveTelemetryStartRequest) async throws -> LiveTelemetryAcquisitionTargets {
        guard let vehicleID = request.vehicleID else {
            guard let discoverSupportedPIDs else { throw OBDPIDTelemetryError.unavailable }
            return try await adapterTargets(for: request, discovery: discoverSupportedPIDs)
        }
        guard let loadVehicleCapabilities else {
            return LiveTelemetryAcquisitionTargets(definitions: try readMajorPIDs.loadDefinitions(), capabilities: [])
        }
        let capabilities = try await loadVehicleCapabilities.execute(
            vehicleID: vehicleID,
            vehicleModelCode: request.vehicleModelCode,
            endpoint: request.endpoint
        )
        let definitions = try readMajorPIDs.loadDefinitions(for: capabilities)
        let enabledByRequest = Dictionary(
            uniqueKeysWithValues: capabilities.map { ($0.id.request, $0.isCollectionEnabled) }
        )
        return makeTargets(definitions: definitions) { enabledByRequest[$0] }
    }

    /// 車両未登録の開始要求について、アダプターへ問い合わせた対応PIDから取得対象を決めます。
    ///
    /// 責務: 保存を伴わない対応PID探索結果を、全件収集有効の取得対象へ変換します。
    /// - Parameters:
    ///   - request: 終端と型式を含む車両未登録の開始要求。
    ///   - discovery: 保存を伴わず対応PIDを探索するユースケース。
    /// - Returns: 対応確認済みの標準PIDと型式一致の車種専用PIDを対象にした取得対象。
    /// - Throws: 探索またはカタログ読込に失敗した場合のエラー。
    private func adapterTargets(
        for request: LiveTelemetryStartRequest,
        discovery: DiscoverSupportedOBDPIDsUseCase
    ) async throws -> LiveTelemetryAcquisitionTargets {
        let supported = Set(
            try await discovery.execute(vehicleModelCode: request.vehicleModelCode, endpoint: request.endpoint)
        )
        let definitions = try readMajorPIDs.loadDefinitions(matching: supported)
        return makeTargets(definitions: definitions) { supported.contains($0) ? true : nil }
    }

    /// 取得対象定義へ対応確認済みの対応状況を付けます。
    ///
    /// 責務: 定義ごとの収集選択を対応確認済みの取得証跡入力へ変換し、選択が無い定義は入力から外します。
    /// - Parameters:
    ///   - definitions: 取得対象として確定した数値化可能PID定義。
    ///   - collectionEnabled: Service/PIDごとの収集選択。対応確認が無い場合は `nil`。
    /// - Returns: 定義と、対応確認済みの定義だけに付けた対応状況。
    private func makeTargets(
        definitions: [OBDPIDDefinition],
        collectionEnabled: (OBDPIDRequest) -> Bool?
    ) -> LiveTelemetryAcquisitionTargets {
        let capabilities = definitions.compactMap { definition -> ConnectionSessionAcquisitionPIDCapabilityInput? in
            let request = OBDPIDRequest(service: definition.service, pid: definition.pid)
            return collectionEnabled(request).map {
                ConnectionSessionAcquisitionPIDCapabilityInput(request: request, support: .supported, isCollectionEnabled: $0)
            }
        }
        return LiveTelemetryAcquisitionTargets(definitions: definitions, capabilities: capabilities)
    }
}

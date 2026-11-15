/// 手動接続と常駐リンクの両方から記録を始めるための確定済み要求です。
///
/// LiveTelemetry の開始要求へは App の配線で写します(Logging は LiveTelemetry の型に依存しません)。
/// 車両ありは登録済み車両の取得、車両なしは未登録車両の取得(標準PIDのみ)になります。
nonisolated struct VehicleRecordingStartRequest: Equatable, Sendable {
    /// 記録に使う接続終端です。
    let endpoint: OBDConnectionEndpoint

    /// 記録へ紐付ける登録済み車両です。車両なしで記録する場合は `nil` です。
    let vehicle: VehicleProfile?

    /// 記録中に観測したVINです。車両未割当のセッションへ残す値で、読めなかった場合は `nil` です。
    let observedVIN: String?

    /// 車種専用PIDの適用に使う型式コードです。該当しない場合は `nil` です。
    let vehicleModelCode: String?

    /// 常駐リンクの初期化時に判定したアダプター判定結果です。判定していない場合は `nil` です。
    let adapterProbeEvidence: AcquisitionAdapterProbeEvidence?

    /// 記録開始に必要な値を固定します。
    ///
    /// 責務: 終端・車両・観測VIN・型式コード・アダプター判定結果を1件の不変値へまとめます。
    /// - Parameters:
    ///   - endpoint: 記録に使う接続終端。
    ///   - vehicle: 記録へ紐付ける登録済み車両。
    ///   - observedVIN: 記録中に観測したVIN。
    ///   - vehicleModelCode: 車種専用PIDの適用に使う型式コード。
    ///   - adapterProbeEvidence: アダプター判定結果。
    init(
        endpoint: OBDConnectionEndpoint,
        vehicle: VehicleProfile?,
        observedVIN: String?,
        vehicleModelCode: String?,
        adapterProbeEvidence: AcquisitionAdapterProbeEvidence?
    ) {
        self.endpoint = endpoint
        self.vehicle = vehicle
        self.observedVIN = observedVIN
        self.vehicleModelCode = vehicleModelCode
        self.adapterProbeEvidence = adapterProbeEvidence
    }

    /// 手動接続で確定した車両とOBD識別観測から記録開始要求を生成します。
    ///
    /// 責務: 手動接続の識別結果を、車両あり・アダプター判定なしの記録開始要求へ変換します。
    /// - Parameters:
    ///   - vehicle: 手動接続で確定した登録済み車両。
    ///   - endpoint: 手動接続で選んだ接続終端。
    ///   - identification: 接続時に読み取ったOBD識別観測。
    /// - Returns: 識別観測のVINまたはOBD識別子から型式コードを決めた要求。観測VINは持ちません。
    @MainActor
    static func manualConnection(
        vehicle: VehicleProfile,
        endpoint: OBDConnectionEndpoint,
        identification: VehicleIdentificationSnapshot
    ) -> VehicleRecordingStartRequest {
        VehicleRecordingStartRequest(
            endpoint: endpoint,
            vehicle: vehicle,
            observedVIN: nil,
            vehicleModelCode: vehicleModelCode(identifiers: [identification.vin, identification.obdIdentifier]),
            adapterProbeEvidence: nil
        )
    }

    /// 手動接続で識別した車両が未登録だった時の、車両なしの記録開始要求を生成します。
    ///
    /// 責務: 手動接続の識別結果を、車両なし・型式コードなし・アダプター判定なしの記録開始要求へ変換します。
    /// - Parameters:
    ///   - endpoint: 手動接続で選んだ接続終端。
    ///   - identification: 接続時に読み取ったOBD識別観測。
    /// - Returns: 標準PIDだけを取得する要求。識別観測のVINは観測VINとして保持します(読めていなければ `nil`)。
    @MainActor
    static func manualUnregisteredConnection(
        endpoint: OBDConnectionEndpoint,
        identification: VehicleIdentificationSnapshot
    ) -> VehicleRecordingStartRequest {
        VehicleRecordingStartRequest(
            endpoint: endpoint,
            vehicle: nil,
            observedVIN: identification.vin,
            vehicleModelCode: nil,
            adapterProbeEvidence: nil
        )
    }

    /// 常駐リンクの記録開始要求と照合済みの登録車両から記録開始要求を生成します。
    ///
    /// 責務: 常駐リンクが読んだVINとアダプター判定結果を、照合結果の車両と組み合わせます。
    /// 型式コードは一致した登録済み車両がある時だけ、その車両のVINとOBD識別子から決めます。
    /// - Parameters:
    ///   - request: 常駐リンク監視からの記録開始要求。
    ///   - vehicle: VINが一致した登録済み車両。一致しない・照合に失敗した場合は `nil`。
    /// - Returns: 記録開始要求。車両が `nil` なら型式コードも `nil`(標準PIDのみ)。読み取ったVINは観測VINとして保持します。
    @MainActor
    static func residentLink(
        _ request: AdapterLinkRecordingStartRequest,
        vehicle: VehicleProfile?
    ) -> VehicleRecordingStartRequest {
        VehicleRecordingStartRequest(
            endpoint: request.endpoint,
            vehicle: vehicle,
            observedVIN: request.vin,
            vehicleModelCode: vehicle.flatMap { vehicleModelCode(identifiers: [$0.vin, $0.obdIdentifier]) },
            adapterProbeEvidence: request.adapterProbeEvidence
        )
    }

    /// 識別子のいずれかがZD8型式に該当する場合に型式コードを返します。
    ///
    /// 責務: 複数の車両識別子を `ZD8VehicleModelPolicy` で判定し、型式コードの有無へ変換します。
    /// - Parameter identifiers: VINやOBD識別子。`nil` や空文字は該当しない扱いです。
    /// - Returns: 1件でも該当すれば `ZD8VehicleModelPolicy.modelCode`、該当しなければ `nil`。
    @MainActor
    static func vehicleModelCode(identifiers: [String?]) -> String? {
        let policy = ZD8VehicleModelPolicy()
        return identifiers.contains { policy.matches($0) } ? ZD8VehicleModelPolicy.modelCode : nil
    }
}

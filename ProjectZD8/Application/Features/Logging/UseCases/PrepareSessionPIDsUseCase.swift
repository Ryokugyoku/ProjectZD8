import Foundation

/// セッション開始前に、車両が応答するPIDを調べて取得条件の一覧を作ります。
nonisolated struct PrepareSessionPIDsUseCase: Sendable {
    /// 準備に失敗した理由です。
    nonisolated enum Failure: Error, Equatable, Sendable {
        /// 収集対象にできるPIDが1件もありません。
        case noPollablePIDs
    }

    private let settings: any VehiclePIDSettingRepository
    private let now: @Sendable () -> Date

    /// 責務: PID設定の保存先と時刻の取得元を受け取ります。
    init(settings: any VehiclePIDSettingRepository, now: @escaping @Sendable () -> Date) {
        self.settings = settings
        self.now = now
    }

    /// 責務: 車両の対応PIDを確認・保存し、並び順を固定した取得条件を返します。
    ///
    /// 同梱定義のうち数式のあるPIDだけを取得対象にします。数式の無い対応PIDと同梱定義に無い対応PIDは、収集無効で一覧に残します。
    /// - Throws: 通信路の `OBDLinkError`、保存の失敗、または取得対象が無い場合は `Failure.noPollablePIDs`。
    func execute(vehicle: Vehicle, link: any OBDLink) async throws -> [SessionPID] {
        let definitions = OBDPIDCatalog.definitions(forVehicleModelCode: vehicle.modelCode)
        var supported = try await link.supportedPIDs()
        for definition in definitions where definition.isVehicleSpecific {
            let result = try await link.query(definition.request, header: definition.header)
            if result.outcome == .responded { supported.insert(definition.request) }
        }
        try await settings.mergeDiscovered(supported, for: vehicle.id, at: now())
        let enabled = Dictionary(
            try await settings.settings(for: vehicle.id).map { ($0.request, $0.isCollectionEnabled) },
            uniquingKeysWith: { _, latest in latest }
        )

        var result: [SessionPID] = []
        for definition in definitions where supported.contains(definition.request) {
            let isDecodable = definition.isDecodable
            result.append(SessionPID(
                ordinal: result.count,
                request: definition.request,
                header: definition.header,
                support: .supported,
                isCollectionEnabled: isDecodable && (enabled[definition.request] ?? true),
                isFastGroup: definition.header == nil && AcquisitionPollingPolicy.defaultFastRequests.contains(definition.request),
                definitionRevision: definition.revision,
                requiredByteCount: definition.requiredByteCount,
                formula: definition.formula,
                unit: definition.unit,
                minimumValue: definition.minimumValue,
                maximumValue: definition.maximumValue
            ))
        }
        let known = Set(definitions.map(\.request))
        let unknown = supported.subtracting(known).sorted { ($0.service, $0.pid) < ($1.service, $1.pid) }
        for request in unknown {
            result.append(SessionPID(
                ordinal: result.count,
                request: request,
                header: nil,
                support: .supported,
                isCollectionEnabled: false,
                isFastGroup: false,
                definitionRevision: 0,
                requiredByteCount: nil,
                formula: nil,
                unit: "",
                minimumValue: nil,
                maximumValue: nil
            ))
        }
        guard result.contains(where: \.isPolled) else { throw Failure.noPollablePIDs }
        return result
    }
}

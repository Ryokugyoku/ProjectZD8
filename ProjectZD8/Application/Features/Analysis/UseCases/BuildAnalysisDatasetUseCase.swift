import Foundation

/// 1セッションの分析用データセットを組み立てます。
nonisolated struct BuildAnalysisDatasetUseCase: Sendable {
    private let decoder: AnalysisSessionDecoder
    private let vehicles: any VehicleRepository
    private let maintenance: any MaintenanceRepository
    private let names: any AnalysisPIDNamePort

    /// ユースケースを生成します。
    ///
    /// 責務: データセットの組み立てに必要な読み出し元を束ねます。
    init(decoder: AnalysisSessionDecoder, vehicles: any VehicleRepository, maintenance: any MaintenanceRepository, names: any AnalysisPIDNamePort) {
        self.decoder = decoder
        self.vehicles = vehicles
        self.maintenance = maintenance
        self.names = names
    }

    /// セッションをページ読みで変換し、メタデータ・品質・欠測区間・整備マーカーを添えて返します。
    ///
    /// 責務: 1セッションのRawを取得時のPIDスナップショットで物理値化し、分析用の列指向データへまとめます。
    /// - Throws: `AnalysisFailure`(セッション・車両の不在、Raw未所持、サンプル無し、読み出し失敗)。
    @concurrent
    func build(sessionID: SessionID) async throws -> AnalysisDataset {
        let decoded = try await decoder.decode(sessionID)
        guard decoded.session.sampleCount > 0 || decoded.channels.contains(where: { $0.quality.requested > 0 }) else {
            throw AnalysisFailure.noSamples
        }
        let vehicle: Vehicle
        let records: [MaintenanceRecord]
        do {
            guard let found = try await vehicles.vehicle(decoded.session.vehicleID) else { throw AnalysisFailure.vehicleNotFound }
            vehicle = found
            records = try await maintenance.records(for: vehicle.id)
        } catch let failure as AnalysisFailure {
            throw failure
        } catch {
            throw AnalysisFailure.store
        }
        let session = decoded.session
        let channels = decoded.channels
            .filter { $0.quality.requested > 0 }
            .map { channel in makeChannel(channel, modelCode: vehicle.modelCode) }
        return AnalysisDataset(
            schemaVersion: AnalysisDataset.currentSchemaVersion,
            session: AnalysisSessionInfo(
                id: session.id.rawValue.uuidString,
                vehicleId: vehicle.id.rawValue.uuidString,
                startedAt: session.startedAt,
                durationSeconds: decoded.durationSeconds,
                isRecording: session.isRecording,
                isDemo: session.isDemo,
                adapterName: session.adapterName,
                platform: session.platform.rawValue,
                appVersion: session.appVersion,
                endReason: session.endReason?.rawValue,
                sampleCount: session.sampleCount,
                respondedCount: session.respondedCount,
                odometerStartKilometers: session.odometerStartKilometers,
                odometerEndKilometers: session.odometerEndKilometers,
                distanceKilometers: session.recordedDistanceKilometers
            ),
            vehicle: AnalysisVehicleInfo(
                id: vehicle.id.rawValue.uuidString,
                name: vehicle.name,
                manufacturer: vehicle.manufacturer,
                engineModel: vehicle.engineModel,
                modelYear: vehicle.modelYear,
                powertrain: vehicle.powertrain.rawValue
            ),
            channels: channels,
            gaps: decoded.gaps,
            maintenance: Self.markers(from: records)
        )
    }

    /// 責務: 変換済みチャンネルへ表示名などのメタデータを付けます。
    private func makeChannel(_ channel: AnalysisDecodedChannel, modelCode: String?) -> AnalysisChannel {
        let pid = channel.pid
        let serviceHex = String(format: "%02X", pid.request.service)
        let pidHex = String(format: "%02X", pid.request.pid)
        let nameKey = OBDPIDCatalog.definition(for: pid.request, vehicleModelCode: modelCode)?.nameKey
        let name = nameKey.map { names.displayName(forKey: $0) } ?? "\(serviceHex) \(pidHex)"
        return AnalysisChannel(
            id: "\(serviceHex)-\(pidHex)",
            serviceHex: serviceHex,
            pidHex: pidHex,
            name: name,
            unit: pid.unit,
            declaredMinimum: pid.minimumValue,
            declaredMaximum: pid.maximumValue,
            isFast: pid.isFastGroup,
            definitionRevision: pid.definitionRevision,
            isDecodable: pid.formula?.isEmpty == false && pid.requiredByteCount != nil,
            times: channel.times,
            values: channel.values,
            quality: channel.quality
        )
    }

    /// 責務: 整備記録を日付昇順のマーカーへ変換します。
    static func markers(from records: [MaintenanceRecord]) -> [AnalysisMaintenanceMarker] {
        records.sorted { $0.performedAt < $1.performedAt }.map {
            AnalysisMaintenanceMarker(
                id: $0.id.rawValue.uuidString,
                date: $0.performedAt,
                title: $0.title,
                kind: $0.kind.rawValue,
                odometerKilometers: $0.odometerKilometers
            )
        }
    }
}

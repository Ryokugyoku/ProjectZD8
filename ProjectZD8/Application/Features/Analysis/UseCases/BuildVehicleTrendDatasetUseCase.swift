import Foundation

/// 1台の車両の長期傾向(セッションごとの運転条件別集計)を組み立てます。
nonisolated struct BuildVehicleTrendDatasetUseCase: Sendable {
    /// 条件別集計を出す最小サンプル数です。これ未満の条件は出力しません。
    static let minimumConditionSampleCount = 5
    /// 他チャンネルの最新値を条件判定に使える最大の遅れ(秒)です。
    static let conditionLookupToleranceSeconds = 2.0
    /// 安定巡航の判定で参照する過去の時間(秒)です。
    static let cruiseLookbackSeconds = 3.0

    private let sessions: any SessionRepository
    private let decoder: AnalysisSessionDecoder
    private let vehicles: any VehicleRepository
    private let maintenance: any MaintenanceRepository
    private let names: any AnalysisPIDNamePort

    /// ユースケースを生成します。
    ///
    /// 責務: 長期傾向の組み立てに必要な読み出し元を束ねます。
    init(sessions: any SessionRepository, decoder: AnalysisSessionDecoder, vehicles: any VehicleRepository, maintenance: any MaintenanceRepository, names: any AnalysisPIDNamePort) {
        self.sessions = sessions
        self.decoder = decoder
        self.vehicles = vehicles
        self.maintenance = maintenance
        self.names = names
    }

    /// 車両の全セッションを変換し、チャンネル×運転条件ごとの中央値・p05・p95を集計します。
    ///
    /// 責務: デモと記録中を除く端末内Rawから、長期ドリフトを見るためのセッション別集計を作ります。
    /// - Parameters:
    ///   - vehicleID: 対象の車両。
    ///   - includeDemo: `true` でデモセッションも集計に含めます(既定は除外)。
    @concurrent
    func build(vehicleID: VehicleID, includeDemo: Bool = false) async throws -> VehicleTrendDataset {
        let vehicle: Vehicle
        let records: [MaintenanceRecord]
        let allSessions: [DriveSession]
        do {
            guard let found = try await vehicles.vehicle(vehicleID) else { throw AnalysisFailure.vehicleNotFound }
            vehicle = found
            records = try await maintenance.records(for: vehicleID)
            allSessions = try await sessions.sessions(for: vehicleID)
        } catch let failure as AnalysisFailure {
            throw failure
        } catch {
            throw AnalysisFailure.store
        }
        var skippedCloudOnly = 0
        var excludedDemo = 0
        var candidates: [DriveSession] = []
        for session in allSessions where !session.isRecording {
            if session.isDemo && !includeDemo { excludedDemo += 1; continue }
            if session.rawAvailability == .cloudOnly { skippedCloudOnly += 1; continue }
            candidates.append(session)
        }
        candidates.sort { $0.startedAt < $1.startedAt }

        var channelMetadata: [String: VehicleTrendChannel] = [:]
        var channelOrder: [String] = []
        var trendSessions: [VehicleTrendSession] = []
        for session in candidates {
            try Task.checkCancellation()
            let decoded = try await decoder.decode(session.id)
            var stats: [VehicleTrendStat] = []
            let classifier = TrendConditionClassifier(channels: decoded.channels)
            for channel in decoded.channels where !channel.values.isEmpty {
                let id = Self.channelID(channel.pid)
                if channelMetadata[id] == nil {
                    channelMetadata[id] = metadata(for: channel.pid, id: id, modelCode: vehicle.modelCode)
                    channelOrder.append(id)
                }
                var byCondition: [VehicleTrendCondition: [Double]] = [.all: channel.values]
                if classifier.isAvailable {
                    for index in channel.times.indices {
                        for condition in [VehicleTrendCondition.warmIdle, .steadyCruise] where classifier.matches(condition, at: channel.times[index]) {
                            byCondition[condition, default: []].append(channel.values[index])
                        }
                    }
                }
                for condition in VehicleTrendCondition.allCases {
                    guard let values = byCondition[condition],
                          values.count >= (condition == .all ? 1 : Self.minimumConditionSampleCount),
                          let quantiles = AnalysisStatistics.quantiles(of: values) else { continue }
                    stats.append(VehicleTrendStat(
                        channelId: id,
                        condition: condition,
                        count: values.count,
                        median: AnalysisStatistics.rounded(quantiles.median, places: 4),
                        p05: AnalysisStatistics.rounded(quantiles.p05, places: 4),
                        p95: AnalysisStatistics.rounded(quantiles.p95, places: 4)
                    ))
                }
            }
            trendSessions.append(VehicleTrendSession(
                id: session.id.rawValue.uuidString,
                startedAt: session.startedAt,
                durationSeconds: decoded.durationSeconds,
                distanceKilometers: session.recordedDistanceKilometers,
                odometerStartKilometers: session.odometerStartKilometers,
                isDemo: session.isDemo,
                sampleCount: session.sampleCount,
                stats: stats
            ))
        }
        return VehicleTrendDataset(
            schemaVersion: VehicleTrendDataset.currentSchemaVersion,
            vehicle: AnalysisVehicleInfo(
                id: vehicle.id.rawValue.uuidString,
                name: vehicle.name,
                manufacturer: vehicle.manufacturer,
                engineModel: vehicle.engineModel,
                modelYear: vehicle.modelYear,
                powertrain: vehicle.powertrain.rawValue
            ),
            channels: channelOrder.compactMap { channelMetadata[$0] },
            sessions: trendSessions,
            maintenance: BuildAnalysisDatasetUseCase.markers(from: records),
            skippedCloudOnlySessions: skippedCloudOnly,
            excludedDemoSessions: excludedDemo
        )
    }

    /// 責務: セッションPIDからチャンネル識別値を作ります。
    static func channelID(_ pid: SessionPID) -> String {
        String(format: "%02X-%02X", pid.request.service, pid.request.pid)
    }

    /// 責務: チャンネルの表示名と単位を解決します。
    private func metadata(for pid: SessionPID, id: String, modelCode: String?) -> VehicleTrendChannel {
        let key = OBDPIDCatalog.definition(for: pid.request, vehicleModelCode: modelCode)?.nameKey
        let name = key.map { names.displayName(forKey: $0) } ?? id.replacingOccurrences(of: "-", with: " ")
        return VehicleTrendChannel(id: id, name: name, unit: pid.unit)
    }
}

/// 速度・回転数・水温から、各時刻が運転条件を満たすかを判定します。
nonisolated private struct TrendConditionClassifier {
    private let speed: AnalysisDecodedChannel?
    private let rpm: AnalysisDecodedChannel?
    private let coolant: AnalysisDecodedChannel?

    /// 責務: 判定に使う3チャンネルを取り出します。
    init(channels: [AnalysisDecodedChannel]) {
        func find(_ service: UInt8, _ pid: UInt8) -> AnalysisDecodedChannel? {
            channels.first { $0.pid.request == OBDPIDRequest(service: service, pid: pid) && !$0.values.isEmpty }
        }
        speed = find(0x01, 0x0D)
        rpm = find(0x01, 0x0C)
        coolant = find(0x01, 0x05)
    }

    /// 条件判定に必要な車速が揃っているかどうかです。
    var isAvailable: Bool { speed != nil }

    /// 責務: 指定時刻が条件を満たすか判定します。必要な値が欠測の時刻は満たしません。
    func matches(_ condition: VehicleTrendCondition, at time: Double) -> Bool {
        let tolerance = BuildVehicleTrendDatasetUseCase.conditionLookupToleranceSeconds
        guard let speedNow = Self.latest(speed, at: time, tolerance: tolerance) else { return false }
        switch condition {
        case .all:
            return true
        case .warmIdle:
            guard speedNow <= 1,
                  let rpmNow = Self.latest(rpm, at: time, tolerance: tolerance),
                  let coolantNow = Self.latest(coolant, at: time, tolerance: tolerance) else { return false }
            return rpmNow >= 400 && rpmNow <= 1_500 && coolantNow >= 80
        case .steadyCruise:
            guard speedNow >= 40,
                  let earlier = Self.latest(speed, at: time - BuildVehicleTrendDatasetUseCase.cruiseLookbackSeconds, tolerance: tolerance) else { return false }
            return abs(speedNow - earlier) <= 3
        }
    }

    /// 責務: 指定時刻以前で許容時間内の最新値を二分探索で返します。無ければ `nil` です。
    private static func latest(_ channel: AnalysisDecodedChannel?, at time: Double, tolerance: Double) -> Double? {
        guard let channel, let first = channel.times.first, time >= first else { return nil }
        var low = 0
        var high = channel.times.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if channel.times[middle] <= time { low = middle } else { high = middle - 1 }
        }
        return time - channel.times[low] <= tolerance ? channel.values[low] : nil
    }
}

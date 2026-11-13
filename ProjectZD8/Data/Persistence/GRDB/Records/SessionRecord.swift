import Foundation
import GRDB

/// `sessions` テーブルの1行です。
nonisolated struct SessionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "sessions"

    var id: String
    var vehicleID: String
    var startedAt: Int64
    var endedAt: Int64?
    var endReason: String?
    var isDemo: Bool
    var adapterName: String
    var adapterTransport: String
    var platform: String
    var deviceID: String
    var deviceName: String
    var appVersion: String
    var appBuild: String
    var pollingPolicyVersion: Int
    var odometerStartKilometers: Double?
    var odometerEndKilometers: Double?
    var distanceSource: String?
    var sampleCount: Int
    var respondedCount: Int
    var payloadByteCount: Int
    var rawAvailability: String
    var archiveDigest: String?
    var modifiedAt: Int64
    var deletedAt: Int64?

    /// 責務: セッションエンティティから行を生成します。
    init(_ session: DriveSession) {
        id = session.id.rowID
        vehicleID = session.vehicleID.rowID
        startedAt = session.startedAt.epochMilliseconds
        endedAt = session.endedAt?.epochMilliseconds
        endReason = session.endReason?.rawValue
        isDemo = session.isDemo
        adapterName = session.adapterName
        adapterTransport = session.adapterTransport.rawValue
        platform = session.platform.rawValue
        deviceID = session.deviceID
        deviceName = session.deviceName
        appVersion = session.appVersion
        appBuild = session.appBuild
        pollingPolicyVersion = session.pollingPolicyVersion
        odometerStartKilometers = session.odometerStartKilometers
        odometerEndKilometers = session.odometerEndKilometers
        distanceSource = session.distanceSource?.rawValue
        sampleCount = session.sampleCount
        respondedCount = session.respondedCount
        payloadByteCount = session.payloadByteCount
        rawAvailability = session.rawAvailability.rawValue
        archiveDigest = session.archiveDigest
        modifiedAt = session.modifiedAt.epochMilliseconds
        deletedAt = nil
    }

    /// 責務: 行をセッションエンティティへ変換します。不正な値は `StoreError.ioFailure` を投げます。
    func entity() throws -> DriveSession {
        guard
            let transport = AdapterTransport(rawValue: adapterTransport),
            let platform = AcquisitionPlatform(rawValue: platform),
            let availability = RawAvailability(rawValue: rawAvailability)
        else { throw StoreError.ioFailure }
        let reason = try endReason.map { raw -> SessionEndReason in
            guard let reason = SessionEndReason(rawValue: raw) else { throw StoreError.ioFailure }
            return reason
        }
        let source = try distanceSource.map { raw -> DistanceSource in
            guard let source = DistanceSource(rawValue: raw) else { throw StoreError.ioFailure }
            return source
        }
        return DriveSession(
            id: try SessionID(rowID: id),
            vehicleID: try VehicleID(rowID: vehicleID),
            startedAt: Date(epochMilliseconds: startedAt),
            endedAt: endedAt.map { Date(epochMilliseconds: $0) },
            endReason: reason,
            isDemo: isDemo,
            adapterName: adapterName,
            adapterTransport: transport,
            platform: platform,
            deviceID: deviceID,
            deviceName: deviceName,
            appVersion: appVersion,
            appBuild: appBuild,
            pollingPolicyVersion: pollingPolicyVersion,
            odometerStartKilometers: odometerStartKilometers,
            odometerEndKilometers: odometerEndKilometers,
            distanceSource: source,
            sampleCount: sampleCount,
            respondedCount: respondedCount,
            payloadByteCount: payloadByteCount,
            rawAvailability: availability,
            archiveDigest: archiveDigest,
            modifiedAt: Date(epochMilliseconds: modifiedAt)
        )
    }
}

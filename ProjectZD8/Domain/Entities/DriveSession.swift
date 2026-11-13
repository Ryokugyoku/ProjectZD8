import Foundation

/// アダプター接続から切断までの1回の取得セッションです。
nonisolated struct DriveSession: Identifiable, Equatable, Codable, Sendable {
    let id: SessionID
    let vehicleID: VehicleID
    let startedAt: Date
    /// 終了日時です。記録中は `nil` で、`endReason` と必ず同時に設定されます。
    var endedAt: Date?
    var endReason: SessionEndReason?
    /// デモモードで取得した模擬データかどうかです。デモは同期・学習の対象外です。
    let isDemo: Bool
    let adapterName: String
    let adapterTransport: AdapterTransport
    let platform: AcquisitionPlatform
    /// 取得した端末のインストール単位の識別値です。
    let deviceID: String
    let deviceName: String
    let appVersion: String
    let appBuild: String
    /// 取得に使ったポーリング方針の版です。
    let pollingPolicyVersion: Int
    var odometerStartKilometers: Double?
    var odometerEndKilometers: Double?
    var distanceSource: DistanceSource?
    /// 記録した要求の総数です(無応答を含む)。
    var sampleCount: Int
    /// データ付きで応答した要求の数です。
    var respondedCount: Int
    /// 応答ペイロードの合計バイト数です。
    var payloadByteCount: Int
    var rawAvailability: RawAvailability
    /// iCloudへ保存したアーカイブのSHA-256です。未アップロードなら `nil` です。
    var archiveDigest: String?
    var modifiedAt: Date

    /// 走行セッションを生成します。
    ///
    /// 責務: 1回の取得セッションの属性と取得条件をまとめます。
    init(
        id: SessionID = SessionID(),
        vehicleID: VehicleID,
        startedAt: Date,
        endedAt: Date? = nil,
        endReason: SessionEndReason? = nil,
        isDemo: Bool,
        adapterName: String,
        adapterTransport: AdapterTransport,
        platform: AcquisitionPlatform,
        deviceID: String,
        deviceName: String,
        appVersion: String,
        appBuild: String,
        pollingPolicyVersion: Int,
        odometerStartKilometers: Double? = nil,
        odometerEndKilometers: Double? = nil,
        distanceSource: DistanceSource? = nil,
        sampleCount: Int = 0,
        respondedCount: Int = 0,
        payloadByteCount: Int = 0,
        rawAvailability: RawAvailability = .local,
        archiveDigest: String? = nil,
        modifiedAt: Date
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endReason = endReason
        self.isDemo = isDemo
        self.adapterName = adapterName
        self.adapterTransport = adapterTransport
        self.platform = platform
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.pollingPolicyVersion = pollingPolicyVersion
        self.odometerStartKilometers = odometerStartKilometers
        self.odometerEndKilometers = odometerEndKilometers
        self.distanceSource = distanceSource
        self.sampleCount = sampleCount
        self.respondedCount = respondedCount
        self.payloadByteCount = payloadByteCount
        self.rawAvailability = rawAvailability
        self.archiveDigest = archiveDigest
        self.modifiedAt = modifiedAt
    }

    /// 記録中かどうかです。
    var isRecording: Bool { endedAt == nil }

    /// ユーザー操作以外の理由で終了したかどうかです。
    var wasInterrupted: Bool { endReason != nil && endReason != .userStopped }

    /// 開始から終了までの時間です。記録中は `nil` です。
    var duration: TimeInterval? { endedAt.map { $0.timeIntervalSince(startedAt) } }

    /// 開始時と終了時の距離計から求めた走行距離です。
    var recordedDistanceKilometers: Double? {
        guard let start = odometerStartKilometers, let end = odometerEndKilometers, end >= start else { return nil }
        return end - start
    }
}

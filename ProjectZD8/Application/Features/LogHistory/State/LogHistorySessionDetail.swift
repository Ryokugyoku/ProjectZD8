import Foundation

/// セッション詳細画面へ表示する内容です。
nonisolated struct LogHistorySessionDetail: Equatable, Sendable {
    /// 一覧と同じ要約です。
    let row: LogHistorySessionRow
    /// 車両名です。見つからなければ `nil` です。
    let vehicleName: String?
    let adapterName: String
    /// 通信経路の表示名キーです。
    let adapterTransportKey: String
    /// 取得した端末の種類の表示名キーです。
    let platformKey: String
    let deviceName: String
    let appVersion: String
    let appBuild: String
    let pollingPolicyVersion: Int
    let odometerStartKilometers: Double?
    let odometerEndKilometers: Double?
    /// 距離の観測元の表示名キーです。
    let distanceSourceKey: String?
    /// 記録した要求の総数です。
    let sampleCount: Int
    /// 応答のあった要求の数です。
    let respondedCount: Int
    /// 応答の無かった要求の数です。
    let noResponseCount: Int
    /// 応答率(0...1)です。要求が無ければ `nil` です。
    let responseRate: Double?
    let payloadByteCount: Int
    /// iCloudアーカイブのSHA-256です。未アップロードなら `nil` です。
    let archiveDigest: String?

    /// 保存済みのセッションから詳細を生成します。
    ///
    /// 責務: セッションの全属性・カウンタ・応答率を表示用の値へ写します。
    init(session: DriveSession, vehicleName: String?) {
        row = LogHistorySessionRow(session: session)
        self.vehicleName = vehicleName
        adapterName = session.adapterName
        adapterTransportKey = "history.detail.transport.\(session.adapterTransport.rawValue)"
        platformKey = "history.detail.platform.\(session.platform.rawValue)"
        deviceName = session.deviceName
        appVersion = session.appVersion
        appBuild = session.appBuild
        pollingPolicyVersion = session.pollingPolicyVersion
        odometerStartKilometers = session.odometerStartKilometers
        odometerEndKilometers = session.odometerEndKilometers
        distanceSourceKey = session.distanceSource.map { "history.detail.distance_source.\($0.rawValue)" }
        sampleCount = session.sampleCount
        respondedCount = session.respondedCount
        noResponseCount = max(0, session.sampleCount - session.respondedCount)
        responseRate = session.sampleCount > 0 ? Double(session.respondedCount) / Double(session.sampleCount) : nil
        payloadByteCount = session.payloadByteCount
        archiveDigest = session.archiveDigest
    }

    /// 応答率の表示用文字列です。要求が無ければ `nil` です。
    var responseRateText: String? { responseRate?.formatted(.percent.precision(.fractionLength(0...1))) }
    /// 応答ペイロード合計の表示用文字列です。
    var payloadSizeText: String { Int64(payloadByteCount).formatted(.byteCount(style: .file)) }
}

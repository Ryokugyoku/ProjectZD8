import Foundation

/// 記録中のLive Activityへ載せる表示内容です。SwiftUI・ActivityKitに依存しない純粋型です。
///
/// iOSとmacOSで共通の判定です(表示はiOSのLive Activityだけが使います)。
nonisolated struct RecordingSessionActivityContent: Equatable, Codable, Sendable {
    /// 車速(Service 01 PID 0D)です。
    static let vehicleSpeedRequest = OBDPIDRequest(service: 0x01, pid: 0x0D)
    /// エンジン回転数(Service 01 PID 0C)です。
    static let engineSpeedRequest = OBDPIDRequest(service: 0x01, pid: 0x0C)
    /// スロットル開度(Service 01 PID 11)です。
    static let throttlePositionRequest = OBDPIDRequest(service: 0x01, pid: 0x11)

    /// 車両名欄の内容です。
    let vehicle: RecordingSessionActivityVehicleLabel
    /// 状態を表すローカライズキーです。
    let statusKey: String
    /// 状態欄の強調です。
    let statusTone: RecordingSessionActivityStatusTone
    /// 車速(km/h)です。
    let vehicleSpeed: RecordingSessionActivityMetric
    /// エンジン回転数(rpm)です。
    let engineSpeed: RecordingSessionActivityMetric
    /// スロットル開度(%)です。
    let throttlePosition: RecordingSessionActivityMetric
    /// このセッションで受信した応答の件数です。
    let receivedResponseCount: Int
    /// 記録を開始した時刻です。
    let startedAt: Date
    /// App Group共有コンテナに保存した車両写真のファイル名です。写真が無ければ `nil` です。
    let vehiclePhotoFileName: String?
    /// 記録終了後の表示に載せる走行時間と最大値です。記録中は `nil` です。
    let endedSummary: RecordingSessionActivityEndedSummary?

    /// 記録が終わった表示かどうかです。
    var isEnded: Bool { endedSummary != nil }
    /// [切断]操作を出すかどうかです。記録中だけ出します。
    var showsDisconnectAction: Bool { !isEnded }
    /// 経過時間のタイマーを進めるかどうかです。記録中だけ進めます。
    var isTimerRunning: Bool { !isEnded }

    /// 取得状態と車両情報から表示内容を生成します。
    ///
    /// 責務: 取得段階を状態キーと強調へ、観測一覧を車速・回転数・スロットル開度へ変換します。
    /// - Parameters:
    ///   - telemetry: PID継続取得の現在状態。
    ///   - vehicleName: 登録済み車両の名称。未登録・不明なら `nil`。
    ///   - startedAt: 記録を開始した時刻。
    ///   - vehiclePhotoFileName: 共有コンテナ内の車両写真ファイル名。無ければ `nil`。
    @MainActor
    init(
        telemetry: LiveTelemetryState,
        vehicleName: String?,
        startedAt: Date,
        vehiclePhotoFileName: String?
    ) {
        self.init(telemetry: telemetry, vehicleName: vehicleName, startedAt: startedAt, vehiclePhotoFileName: vehiclePhotoFileName, endedSummary: nil)
    }

    /// 記録が終わった時点の取得状態から、終了表示の内容を生成します。
    ///
    /// 責務: 走行時間を開始〜終了の固定値にし、最大値とあわせて終了表示の内容へ変換します。終了理由によらず終了表示にします。
    /// - Parameters:
    ///   - endedTelemetry: 終了時点のPID継続取得の状態。
    ///   - vehicleName: 登録済み車両の名称。未登録・不明なら `nil`。
    ///   - startedAt: 記録を開始した時刻。
    ///   - endedAt: 記録が終わった時刻。
    ///   - maximums: セッション中の項目別最大値。
    ///   - vehiclePhotoFileName: 共有コンテナ内の車両写真ファイル名。無ければ `nil`。
    @MainActor
    init(
        endedTelemetry: LiveTelemetryState,
        vehicleName: String?,
        startedAt: Date,
        endedAt: Date,
        maximums: RecordingSessionActivityMaximums,
        vehiclePhotoFileName: String?
    ) {
        self.init(
            telemetry: endedTelemetry,
            vehicleName: vehicleName,
            startedAt: startedAt,
            vehiclePhotoFileName: vehiclePhotoFileName,
            endedSummary: RecordingSessionActivityEndedSummary(startedAt: startedAt, endedAt: endedAt, maximums: maximums)
        )
    }

    /// 取得状態・車両情報・終了情報から表示内容を生成します。
    ///
    /// 責務: 記録中と終了表示で共通の変換を1か所に持ちます。
    @MainActor
    private init(
        telemetry: LiveTelemetryState,
        vehicleName: String?,
        startedAt: Date,
        vehiclePhotoFileName: String?,
        endedSummary: RecordingSessionActivityEndedSummary?
    ) {
        let status = RecordingSessionActivityStatus(telemetry: telemetry)
        vehicle = RecordingSessionActivityVehicleLabel(vehicleName: vehicleName)
        statusKey = status.key
        statusTone = status.tone
        vehicleSpeed = RecordingSessionActivityMetric(Self.vehicleSpeedRequest, in: telemetry.samples)
        engineSpeed = RecordingSessionActivityMetric(Self.engineSpeedRequest, in: telemetry.samples)
        throttlePosition = RecordingSessionActivityMetric(Self.throttlePositionRequest, in: telemetry.samples)
        receivedResponseCount = telemetry.receivedResponseCount
        self.startedAt = startedAt
        self.vehiclePhotoFileName = vehiclePhotoFileName
        self.endedSummary = endedSummary
    }
}

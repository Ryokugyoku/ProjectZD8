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
    }
}

/// 接続から記録終了までの進行段階です。
nonisolated enum DriveSessionPhase: Equatable, Sendable {
    /// 何もしていません。
    case idle
    /// アダプターへ接続しています。
    case connecting
    /// 車両のVINとアダプター情報を読み取っています。
    case identifying
    /// 未登録のVINです。車両名の入力を待っています。
    case awaitingVehicleRegistration(VehicleIdentification)
    /// 対応PIDを確認し、取得条件を準備しています。
    case preparing
    /// 記録中です。
    case recording
    /// 停止しています。
    case stopping

    /// 画面表示用のローカライズキーです。
    var localizationKey: String {
        switch self {
        case .idle: "drive.phase.idle"
        case .connecting: "drive.phase.connecting"
        case .identifying: "drive.phase.identifying"
        case .awaitingVehicleRegistration: "drive.phase.awaitingVehicleRegistration"
        case .preparing: "drive.phase.preparing"
        case .recording: "drive.phase.recording"
        case .stopping: "drive.phase.stopping"
        }
    }

    /// 新しい接続を受け付けられる状態かどうかです。
    var isIdle: Bool { self == .idle }
}

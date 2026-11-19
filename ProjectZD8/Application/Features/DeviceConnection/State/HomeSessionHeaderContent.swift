import Foundation

/// 接続中のホームに出すセッション見出し(車両名・記録状態・切断操作)の表示内容です。
///
/// iOSとmacOSで共通の判定です。
struct HomeSessionHeaderContent: Equatable {
    /// 見出しに出す車両の表し方です。
    let vehicle: HomeVehicleLabel
    /// 記録状態です。
    let recording: HomeRecordingStatus
    /// 切断操作を押せるかどうかです。切断処理の完了を待つ間は `false` です。
    let isDisconnectEnabled: Bool

    /// リアルタイム表示の状態・記録中のセッション・登録車両から見出しの内容を生成します。
    ///
    /// 責務: 接続中の車両名・記録状態・切断可否を見出しの表示内容へ変換します。
    /// - Parameters:
    ///   - telemetry: 現在のリアルタイム表示状態。
    ///   - activeSession: 記録中の接続セッション。なければ `nil`。
    ///   - vehicles: 登録済み車両の一覧。
    init(telemetry: LiveTelemetryState, activeSession: ConnectionSession?, vehicles: [VehicleProfile]) {
        vehicle = Self.vehicleLabel(context: telemetry.vehicle, activeSession: activeSession, vehicles: vehicles)
        recording = Self.recordingStatus(activeSession: activeSession)
        isDisconnectEnabled = !telemetry.isDisconnecting
    }

    /// 車両の表し方を決めます。
    ///
    /// 責務: 監視中の車両を、登録車両の名称・セッションの車両名・未登録・名称なしのいずれかへ変換します。
    /// - Parameters:
    ///   - context: 監視中の車両。取得を始めていなければ `nil`。
    ///   - activeSession: 記録中の接続セッション。
    ///   - vehicles: 登録済み車両の一覧。
    /// - Returns: 見出しに出す車両の表し方。
    private static func vehicleLabel(
        context: LiveTelemetryVehicleContext?,
        activeSession: ConnectionSession?,
        vehicles: [VehicleProfile]
    ) -> HomeVehicleLabel {
        guard let context else { return .unnamed }
        guard let id = context.vehicleID else { return .unregistered }
        let profileName = displayableName(vehicles.first { $0.id == id }?.name)
        guard let name = profileName ?? displayableName(activeSession?.vehicle?.name) else { return .unnamed }
        return .named(name)
    }

    /// 表示できる車両名へ整えます。
    ///
    /// 責務: 車両名の前後の空白を除き、空なら表示できないものとして扱います。
    /// - Parameter name: 元の車両名。
    /// - Returns: 前後の空白を除いた空でない名称。なければ `nil`。
    private static func displayableName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// 記録状態を決めます。
    ///
    /// 責務: 終了していないセッションがある時だけ記録中と判定します。
    /// - Parameter activeSession: 記録中の接続セッション。
    /// - Returns: 未終了のセッションがあれば開始時刻付きの記録中、なければ記録なし。
    private static func recordingStatus(activeSession: ConnectionSession?) -> HomeRecordingStatus {
        guard let activeSession, activeSession.endedAt == nil else { return .notRecording }
        return .recording(startedAt: activeSession.startedAt)
    }
}

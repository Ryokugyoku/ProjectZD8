import Observation

/// 通知で承認された接続要求を認証完了まで一時保持します。
@MainActor
@Observable
final class PromptedVehicleConnectionRequestBuffer {
    /// 未処理の承認済み接続終端です。
    private(set) var pendingEndpoint: OBDConnectionEndpoint?

    /// 空の接続要求バッファーを生成します。
    ///
    /// 責務: 承認済み接続要求を持たない初期状態を構築します。
    init() {}

    /// 承認済み接続終端を未処理要求として保持します。
    ///
    /// 責務: 最新の承認済み接続要求を1件だけ保持します。
    /// - Parameter endpoint: ユーザーが通知で接続を了承した終端。
    func store(_ endpoint: OBDConnectionEndpoint) {
        pendingEndpoint = endpoint
    }

    /// 未処理の接続終端を取り出してバッファーを空にします。
    ///
    /// 責務: 現在の承認済み接続要求を高々1件だけ消費します。
    /// - Returns: 保持されていた接続終端。要求がなければ `nil`。
    func consume() -> OBDConnectionEndpoint? {
        defer { pendingEndpoint = nil }
        return pendingEndpoint
    }
}

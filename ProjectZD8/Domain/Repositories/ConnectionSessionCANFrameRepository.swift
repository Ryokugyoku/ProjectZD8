/// 受信CANフレームを接続セッション単位で永続化する能力です。
nonisolated protocol ConnectionSessionCANFrameRepository: Sendable {
    /// CANフレーム配列を1件のまとまりとして保存します。
    ///
    /// 責務: 採番済みフレーム配列を全件保存するか1件も保存しないかのどちらかで指定セッションへ追加します。
    /// - Parameters:
    ///   - frames: 呼び出し側が採番した保存対象フレーム。空配列は何も保存せず成功します。
    ///   - sessionID: フレームを所有する接続セッション。
    /// - Throws: 記録順序の重複・所属区間の不在・範囲外の値は
    ///   `ConnectionSessionRepositoryError.integrityConflict`、それ以外の保存失敗は `.unavailable`。
    ///   失敗した場合は配列内のどのフレームも保存されません。
    func saveFrames(_ frames: [CANFrameObservation], for sessionID: ConnectionSessionID) throws

    /// セッションのCANフレームを記録順で返します。
    ///
    /// 責務: 1件のセッションに保存された全CANフレームを安定順で復元します。
    /// - Parameter sessionID: 読取対象の接続セッション。
    /// - Returns: `sequence` 昇順のフレーム。フレームがないセッションでは空配列。
    /// - Throws: 保存値をDomainへ復元できない場合は `ConnectionSessionRepositoryError.integrityConflict`、
    ///   それ以外の読取失敗は `.unavailable`。
    func frames(for sessionID: ConnectionSessionID) throws -> [CANFrameObservation]
}

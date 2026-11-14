/// `ATMA`受信監視の試行結果から取得方式を選びます。
nonisolated struct OBDAcquisitionModeSelectionPolicy: Sendable {
    /// 試行結果を取得方式の判断へ変換します。
    ///
    /// 責務: 受信できればCAN監視、バッファー超過ならフィルター付きCAN監視、非対応・バスエラーならPIDポーリング、
    /// 無受信・停止なら判断保留にします。
    /// - Parameter outcome: `ATMA`応答の分類結果。
    /// - Returns: 取得方式の判断。
    func decide(for outcome: OBDMonitorProbeOutcome) -> OBDAcquisitionModeDecision {
        switch outcome {
        case .framesReceived: .canMonitorUnfiltered
        case .bufferFull: .canMonitorFiltered
        case .unsupported, .busError: .pidPolling
        case .silent, .stopped: .undetermined
        }
    }
}

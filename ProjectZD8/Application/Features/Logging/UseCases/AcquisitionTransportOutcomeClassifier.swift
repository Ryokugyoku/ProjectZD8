/// Transport観測を取得証跡のrequest結果と分類理由へ変換します。
nonisolated struct AcquisitionTransportOutcomeClassifier: Sendable {
    /// 状態を持たない分類器を生成します。
    ///
    /// 責務: 分類規則だけを持つ値を構築します。
    init() {}

    /// Transport観測を取得証跡のrequest結果へ分類します。
    ///
    /// 責務: 1件のTransport観測を推測なしのDomain結果と承認済み理由codeへ変換します。
    /// - Parameter outcome: Transport境界が返した排他結果。
    /// - Returns: Domainのrequest結果と、正応答以外の理由code(正応答では `nil`)。
    func classify(
        _ outcome: OBDPIDRequestTransportOutcome
    ) -> (transportOutcome: PIDRequestTransportOutcome, reasonCode: String?) {
        switch outcome {
        case .responded:
            return (.responded, nil)
        case .unsupported:
            return (.unsupported, "explicit_unsupported")
        case .timedOut:
            return (.timedOut, "response_timeout")
        case .cancelled:
            return (.cancelled, "explicit_cancellation")
        case .transportFailure:
            return (.transportFailure, "transport_boundary_lost")
        case .unclassifiedResponse:
            return (.unclassifiedResponse, "unclassified_transport_result")
        }
    }

    /// request結果列からbatchの失敗理由を決めます。
    ///
    /// 責務: 排他的なrequest結果列を取消・通信不能・未分類・失敗なしへ集約します。
    /// - Parameter outcomes: 終端まで確定したrequest結果列。
    /// - Returns: batchの失敗理由。すべて失敗を含まない場合は `nil`。
    func batchFailure(for outcomes: [PIDRequestTransportOutcome]) -> AcquisitionBatchFailure? {
        if outcomes.contains(.cancelled) { return .cancelled }
        if outcomes.contains(.transportFailure) || outcomes.contains(.timedOut) { return .transportUnavailable }
        if outcomes.contains(.unclassifiedResponse) { return .unclassifiedResult }
        return nil
    }
}

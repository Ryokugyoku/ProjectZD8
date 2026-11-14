/// 応答駆動の取得ループが購読者へ流す出来事です。
nonisolated enum LiveTelemetryAcquisitionEvent: Equatable, Sendable {
    /// 正応答のあった最初の周回が終わり、以後の取得対象が確定しました。polling policyの基準周回の順に並びます。
    case targetsConfirmed([OBDPIDDefinition])
    /// 1件の正応答を数値化しました。
    case sampleDecoded(OBDPIDSample)
    /// 取得・回復中・一時停止の段階が変わりました。
    case phaseChanged(LiveTelemetryAcquisitionPhase)
    /// 取得ループが終わりました。この後に出来事は流れません。
    case ended(LiveTelemetryAcquisitionTermination)
}

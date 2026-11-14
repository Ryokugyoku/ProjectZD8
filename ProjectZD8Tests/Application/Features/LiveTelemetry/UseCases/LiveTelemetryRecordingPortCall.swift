import Foundation
@testable import ProjectZD8

/// 記録ポートのスパイが受けた呼び出しです。
enum LiveTelemetryRecordingPortCall: Equatable {
    /// 取得記録の開始です。
    case start(generation: UInt)
    /// 1周回の開始です。
    case beginRound(LiveTelemetryAcquisitionRoundInput)
    /// 要求1件の結果です。
    case record(LiveTelemetryRequestResult)
    /// 1周回の終了です。
    case finishRound(generation: UInt, batchOrdinal: Int64)
    /// 件数や経過によらない保存の指示です。
    case flush(LiveTelemetryAcquisitionFlushTrigger, generation: UInt)
    /// 取得記録の終了です。
    case finish(generation: UInt, reason: ConnectionSessionEndReason)
}

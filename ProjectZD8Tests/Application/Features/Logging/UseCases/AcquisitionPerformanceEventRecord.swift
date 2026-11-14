@testable import ProjectZD8

/// 性能eventのスパイが記録した1件のeventです。
enum AcquisitionPerformanceEventRecord: Equatable {
    /// 区間の開始です。
    case begin(AcquisitionPerformanceOperation, generation: UInt?)
    /// DB Queueの通過です。
    case queue(AcquisitionPerformanceOperation)
    /// 結果付きの区間終了です。
    case end(AcquisitionPerformanceOperation, AcquisitionPerformanceOutcome)
}

import Foundation
@testable import ProjectZD8

/// 通知された性能eventを順に記録する性能event境界です。
final class AcquisitionPerformanceEventSpy: AcquisitionPerformanceEventPort, @unchecked Sendable {
    /// 記録を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した次の区間番号です。
    private var nextIdentifier: UInt64 = 1
    /// ロックで保護した記録済みeventです。
    private var storedEvents: [AcquisitionPerformanceEventRecord] = []

    /// 空の記録で生成します。
    ///
    /// 責務: eventを1件も持たないスパイを構築します。
    init() {}

    /// 記録済みeventです。通知順に並びます。
    var events: [AcquisitionPerformanceEventRecord] {
        lock.withLock { storedEvents }
    }

    /// 区間の開始を記録します。
    ///
    /// 責務: 開始eventを記録し、一意な区間を返します。
    /// - Parameters:
    ///   - operation: 計測する操作。
    ///   - context: 匿名の取得位置。
    /// - Returns: 区間。
    func begin(_ operation: AcquisitionPerformanceOperation, context: AcquisitionPerformanceContext) -> AcquisitionPerformanceInterval {
        lock.withLock {
            storedEvents.append(.begin(operation, generation: context.generation))
            defer { nextIdentifier += 1 }
            return AcquisitionPerformanceInterval(identifier: nextIdentifier, operation: operation, context: context)
        }
    }

    /// DB Queueの通過を記録します。
    ///
    /// 責務: 通過eventを記録します。
    /// - Parameter interval: 開始済みの区間。
    func queueDidEnter(_ interval: AcquisitionPerformanceInterval) {
        lock.withLock { storedEvents.append(.queue(interval.operation)) }
    }

    /// 区間の終了を記録します。
    ///
    /// 責務: 結果付きの終了eventを記録します。
    /// - Parameters:
    ///   - interval: 開始済みの区間。
    ///   - outcome: 完了結果。
    func end(_ interval: AcquisitionPerformanceInterval, outcome: AcquisitionPerformanceOutcome) {
        lock.withLock { storedEvents.append(.end(interval.operation, outcome)) }
    }
}

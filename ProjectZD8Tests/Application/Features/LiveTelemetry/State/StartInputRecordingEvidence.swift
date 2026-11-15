import Foundation
@testable import ProjectZD8

/// 開始入力を記録し、batchには定義ごとの固定sampleを返す取得証跡境界のフェイクです。
final class StartInputRecordingEvidence: LiveTelemetryAcquisitionEvidencePort, @unchecked Sendable {
    /// 記録への並行アクセスを直列化します。
    private let lock = NSLock()
    /// 受け取った開始入力の記録です。
    private var recorded: [LiveTelemetryAcquisitionStartInput] = []

    /// 受け取った開始入力の一覧です。
    var startInputs: [LiveTelemetryAcquisitionStartInput] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// 開始入力を記録します。
    ///
    /// 責務: 取得証跡の開始要求を検証用に保持します。
    /// - Parameter input: 取得開始入力。
    func start(_ input: LiveTelemetryAcquisitionStartInput) async throws {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(input)
    }

    /// batchの定義ごとに固定値のsampleを返します。
    ///
    /// 責務: 取得loopを継続させる応答済みsampleを返します。
    /// - Parameter input: 取得loopが割り当てたbatch入力。
    /// - Returns: 定義ごとの値42のsample。
    func acquire(_ input: LiveTelemetryAcquisitionBatchInput) async throws -> [OBDPIDSample] {
        input.definitions.map { definition in
            OBDPIDSample(
                request: OBDPIDRequest(service: definition.service, pid: definition.pid),
                nameKey: definition.nameKey,
                value: 42,
                unit: definition.unit,
                vehicleModelCode: definition.vehicleModelCode,
                observedAt: input.startedAt,
                summaryKey: definition.summaryKey,
                highValueKey: definition.highValueKey,
                lowValueKey: definition.lowValueKey,
                correlationKey: definition.correlationKey
            )
        }
    }

    /// 世代取消しを受け付けます。
    ///
    /// 責務: 停止時の取消要求を副作用なしで完了します。
    /// - Parameter generation: 取消対象世代。
    func cancel(generation: UInt) async {}
}

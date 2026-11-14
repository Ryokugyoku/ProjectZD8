import Foundation
@testable import ProjectZD8

/// 取得ループから受けた記録の呼び出しを順に記録し、指定した呼び出しだけ失敗させる記録ポートです。
///
/// 記録は複数のタスクから届くため、ロックで直列化します。
final class LiveTelemetryRecordingPortSpy: LiveTelemetryAcquisitionRecordingPort, @unchecked Sendable {
    /// 記録への並行アクセスを直列化するロックです。
    private let lock = NSLock()
    /// ロックで保護した受けた呼び出しです。
    private var storedCalls: [LiveTelemetryRecordingPortCall] = []
    /// ロックで保護した受けた開始入力です。
    private var storedStartInputs: [LiveTelemetryAcquisitionStartInput] = []
    /// 失敗させる呼び出しです。
    private let failurePoint: LiveTelemetryRecordingFailurePoint?

    /// 失敗させる呼び出しを固定して生成します。
    ///
    /// 責務: 呼び出しを記録し、指定した呼び出しだけ保存失敗にするスパイを構築します。
    /// - Parameter failurePoint: 失敗させる呼び出し。`nil` ならすべて成功します。
    init(failing failurePoint: LiveTelemetryRecordingFailurePoint? = nil) {
        self.failurePoint = failurePoint
    }

    /// 受けた呼び出しです。受けた順に並びます。
    var calls: [LiveTelemetryRecordingPortCall] {
        lock.withLock { storedCalls }
    }

    /// 受けた開始入力です。受けた順に並びます。
    var startInputs: [LiveTelemetryAcquisitionStartInput] {
        lock.withLock { storedStartInputs }
    }

    /// 受けた要求結果です。受けた順に並びます。
    var recordedResults: [LiveTelemetryRequestResult] {
        calls.compactMap { if case let .record(result) = $0 { result } else { nil } }
    }

    /// 受けた周回開始です。受けた順に並びます。
    var roundInputs: [LiveTelemetryAcquisitionRoundInput] {
        calls.compactMap { if case let .beginRound(input) = $0 { input } else { nil } }
    }

    /// 受けた終了です。受けた順に並びます。
    var finishCalls: [LiveTelemetryRecordingPortCall] {
        calls.filter { if case .finish = $0 { true } else { false } }
    }

    /// 開始を記録します。
    ///
    /// 責務: 開始入力を記録し、指定時は保存失敗を送出します。
    /// - Parameter input: 取得開始入力。
    /// - Throws: `start` を失敗させる場合は `.storageFailed`。
    func start(_ input: LiveTelemetryAcquisitionStartInput) async throws {
        lock.withLock { storedStartInputs.append(input) }
        try append(.start(generation: input.generation), at: .start)
    }

    /// 周回開始を記録します。
    ///
    /// 責務: 周回入力を記録し、指定時は保存失敗を送出します。
    /// - Parameter input: 周回入力。
    /// - Throws: `beginRound` を失敗させる場合は `.storageFailed`。
    func beginRound(_ input: LiveTelemetryAcquisitionRoundInput) async throws {
        try append(.beginRound(input), at: .beginRound)
    }

    /// 要求結果を記録します。
    ///
    /// 責務: 要求結果を記録し、指定時は保存失敗を送出します。
    /// - Parameter result: 要求1件の結果。
    /// - Throws: `record` を失敗させる場合は `.storageFailed`。
    func record(_ result: LiveTelemetryRequestResult) async throws {
        try append(.record(result), at: .record)
    }

    /// 周回終了を記録します。
    ///
    /// 責務: 周回終了を記録し、指定時は保存失敗を送出します。
    /// - Parameters:
    ///   - generation: 世代。
    ///   - batchOrdinal: batch番号。
    /// - Throws: `finishRound` を失敗させる場合は `.storageFailed`。
    func finishRound(generation: UInt, batchOrdinal: Int64) async throws {
        try append(.finishRound(generation: generation, batchOrdinal: batchOrdinal), at: .finishRound)
    }

    /// 保存指示を記録します。
    ///
    /// 責務: 保存の契機と世代を記録し、指定時は保存失敗を送出します。
    /// - Parameters:
    ///   - trigger: 保存の契機。
    ///   - generation: 世代。
    /// - Throws: `flush` を失敗させる場合は `.storageFailed`。
    func flush(_ trigger: LiveTelemetryAcquisitionFlushTrigger, generation: UInt) async throws {
        try append(.flush(trigger, generation: generation), at: .flush)
    }

    /// 終了を記録します。
    ///
    /// 責務: 終了の世代と原因を記録し、指定時は保存失敗を送出します。
    /// - Parameters:
    ///   - generation: 世代。
    ///   - reason: 終了原因。
    /// - Throws: `finish` を失敗させる場合は `.storageFailed`。
    func finish(generation: UInt, reason: ConnectionSessionEndReason) async throws {
        try append(.finish(generation: generation, reason: reason), at: .finish)
    }

    /// 呼び出しを記録し、指定した呼び出しなら保存失敗を送出します。
    ///
    /// 責務: ロック下で呼び出しを追加し、呼び出し種別と失敗指定を照合します。
    /// - Parameters:
    ///   - call: 受けた呼び出し。
    ///   - point: 現在の呼び出し種別。
    /// - Throws: 失敗指定と一致する場合は `.storageFailed`。
    private func append(_ call: LiveTelemetryRecordingPortCall, at point: LiveTelemetryRecordingFailurePoint) throws {
        lock.withLock { storedCalls.append(call) }
        if failurePoint == point { throw LiveTelemetryAcquisitionRecordingError.storageFailed }
    }
}

import Foundation
import XCTest
@testable import ProjectZD8

/// 受けた要求を記録し、テストが明示的に応答を解放するまで待たせるPID取得境界のフェイクです。
///
/// 要求ごとに continuation を保持し、`release(_:)` で1件ずつ結果を返します。
/// 取消されたTaskの要求は取消として返し、待たせたままにしません。
@MainActor
final class GatedOBDPIDTelemetryFake: OBDPIDTelemetryPort {
    /// 応答待ちの要求です。
    private struct Pending {
        /// 取消と解放を対応付ける番号です。
        let identifier: Int
        /// 送られた要求です。
        let request: OBDPIDRequest
        /// 応答を返す continuation です。
        let continuation: CheckedContinuation<OBDPIDRequestTransportOutcome, Never>
    }

    /// 送られた要求です。送信順に並びます。
    private(set) var sentRequests: [OBDPIDRequest] = []
    /// 1回の呼び出しで渡された要求の件数です。呼び出し順に並びます。
    private(set) var requestCountsPerCall: [Int] = []
    /// `endSession` が呼ばれた回数です。
    private(set) var endSessionCount = 0
    /// 応答待ちの要求です。
    private var pending: Pending?
    /// 次に割り当てる要求番号です。
    private var nextIdentifier = 0

    /// 空の記録で生成します。
    ///
    /// 責務: 要求を1件も受けていないフェイクを構築します。
    init() {}

    /// 応答待ちの要求です。無ければ `nil` です。
    var pendingRequest: OBDPIDRequest? { pending?.request }

    /// 標準PIDの要求を受け、解放されるまで待ちます。
    ///
    /// 責務: 要求を記録し、テストが解放した結果を Transport 観測として返します。
    /// - Parameters:
    ///   - requests: 送られた要求。
    ///   - endpoint: 使用するOBD終端。
    /// - Returns: 解放された結果を持つ観測。
    func readObservations(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequestTransportObservation] {
        var observations: [OBDPIDRequestTransportObservation] = []
        requestCountsPerCall.append(requests.count)
        for request in requests {
            let outcome = await awaitRelease(of: request)
            observations.append(OBDPIDRequestTransportObservation(request: request, outcome: outcome))
        }
        return observations
    }

    /// 標準PIDの要求を受け、正応答だけを辞書で返します。
    ///
    /// 責務: `readObservations` と同じ待ち合わせで、正応答のpayloadだけを返します。
    /// - Parameters:
    ///   - requests: 送られた要求。
    ///   - endpoint: 使用するOBD終端。
    /// - Returns: 正応答の要求とpayload。
    func read(_ requests: [OBDPIDRequest], using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest: [UInt8]] {
        let observations = try await readObservations(requests, using: endpoint)
        return Dictionary(uniqueKeysWithValues: observations.compactMap { observation in
            guard case let .responded(payload) = observation.outcome else { return nil }
            return (observation.request, payload)
        })
    }

    /// 車種専用PIDの要求を受け、解放されるまで待ちます。
    ///
    /// 責務: 要求を記録し、正応答なら辞書で返し、取消なら `CancellationError` を送出します。
    /// - Parameters:
    ///   - definitions: 送られた車種専用定義。
    ///   - endpoint: 使用するOBD終端。
    /// - Returns: 正応答の要求とpayload。正応答以外は空です。
    /// - Throws: 取消を解放された場合は `CancellationError`。
    func readVehicleSpecific(
        _ definitions: [OBDPIDDefinition],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        requestCountsPerCall.append(definitions.count)
        var responses: [OBDPIDRequest: [UInt8]] = [:]
        for definition in definitions {
            let request = OBDPIDRequest(service: definition.service, pid: definition.pid)
            switch await awaitRelease(of: request) {
            case let .responded(payload): responses[request] = payload
            case .cancelled: throw CancellationError()
            default: break
            }
        }
        return responses
    }

    /// 接続資源の解放を記録します。
    ///
    /// 責務: `endSession` の呼び出し回数を数えます。
    func endSession() async {
        endSessionCount += 1
    }

    /// 応答待ちの要求へ結果を1件返します。
    ///
    /// 責務: 要求が届くまで上限付きで待ち、届いた要求へ指定結果を返します。上限を超えたら失敗させます。
    /// - Parameters:
    ///   - outcome: 返す結果。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    /// - Returns: 結果を返した要求。要求が届かなかった場合は `nil`。
    @discardableResult
    func release(
        _ outcome: OBDPIDRequestTransportOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> OBDPIDRequest? {
        let arrived = await LiveTelemetryBoundedWaiter.waitUntil("要求の到着", file: file, line: line) {
            self.pending != nil
        }
        guard arrived, let pending else { return nil }
        self.pending = nil
        pending.continuation.resume(returning: outcome)
        return pending.request
    }

    /// 送信済み要求が指定件数に達するまで上限付きで待ちます。
    ///
    /// 責務: 送信件数の到達を待ち、上限を超えたら失敗させます。
    /// - Parameters:
    ///   - count: 待つ送信件数。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    /// - Returns: 到達した場合は `true`。
    @discardableResult
    func waitForSentRequests(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async -> Bool {
        await LiveTelemetryBoundedWaiter.waitUntil("送信済み要求 \(count) 件", file: file, line: line) {
            self.sentRequests.count >= count
        }
    }

    /// 届いた要求ごとに結果を決めて指定件数だけ返します。
    ///
    /// 責務: `release(_:)` を件数分繰り返し、途中で要求が届かなければ失敗として止めます。
    /// - Parameters:
    ///   - count: 返す件数。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    ///   - outcome: 要求から結果を決める処理。
    /// - Returns: 全件返せた場合は `true`。
    @discardableResult
    func answer(
        _ count: Int,
        file: StaticString = #filePath,
        line: UInt = #line,
        with outcome: (OBDPIDRequest) -> OBDPIDRequestTransportOutcome
    ) async -> Bool {
        for _ in 0..<count {
            let arrived = await LiveTelemetryBoundedWaiter.waitUntil("要求の到着", file: file, line: line) {
                self.pending != nil
            }
            guard arrived, let request = pending?.request else { return false }
            await release(outcome(request), file: file, line: line)
        }
        return true
    }

    /// 要求を記録し、解放または取消まで待ちます。
    ///
    /// 責務: 1件の要求の continuation を保持し、Taskが取消された場合は取消を返します。
    /// - Parameter request: 送られた要求。
    /// - Returns: 解放された結果、または取消。
    private func awaitRelease(of request: OBDPIDRequest) async -> OBDPIDRequestTransportOutcome {
        sentRequests.append(request)
        let identifier = nextIdentifier
        nextIdentifier += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: .cancelled)
                    return
                }
                pending = Pending(identifier: identifier, request: request, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor in self.cancelPending(identifier: identifier) }
        }
    }

    /// 取消されたTaskの応答待ちを取消として解放します。
    ///
    /// 責務: 番号が一致する応答待ちだけを取消で返します。
    /// - Parameter identifier: 取消された要求の番号。
    private func cancelPending(identifier: Int) {
        guard let pending, pending.identifier == identifier else { return }
        self.pending = nil
        pending.continuation.resume(returning: .cancelled)
    }
}

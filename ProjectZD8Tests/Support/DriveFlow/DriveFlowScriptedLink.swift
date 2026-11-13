import Foundation
@testable import ProjectZD8

/// 要求ごとの応答を台本で決める `OBDLink` です。
final class DriveFlowScriptedLink: OBDLink, @unchecked Sendable {
    /// 1件の要求への応答を決める台本です。`callIndex` は通算の要求番号(0始まり)です。
    typealias Script = @Sendable (_ request: OBDPIDRequest, _ header: UInt16?, _ callIndex: Int) throws -> OBDQueryResult

    struct Query: Hashable {
        let request: OBDPIDRequest
        let header: UInt16?
    }

    private let lock = NSLock()
    private let identification: Result<VehicleIdentification, OBDLinkError>
    private let supported: Set<OBDPIDRequest>
    private let script: Script
    private let clock: DriveFlowManualClock?
    private let queryDuration: Int64
    private var recordedQueries: [Query] = []
    private var closes = 0
    private let onQuery: (@Sendable (Int) -> Void)?

    init(
        identification: Result<VehicleIdentification, OBDLinkError> = .success(DriveFlowFixtures.identification()),
        supported: Set<OBDPIDRequest> = DriveFlowFixtures.fastRequests,
        clock: DriveFlowManualClock? = nil,
        queryDuration: Int64 = 0,
        onQuery: (@Sendable (Int) -> Void)? = nil,
        script: @escaping Script = { _, _, _ in OBDQueryResult(outcome: .responded, payload: [50, 50]) }
    ) {
        self.identification = identification
        self.supported = supported
        self.clock = clock
        self.queryDuration = queryDuration
        self.onQuery = onQuery
        self.script = script
    }

    func identify() async throws -> VehicleIdentification { try identification.get() }

    func supportedPIDs() async throws -> Set<OBDPIDRequest> { supported }

    func query(_ request: OBDPIDRequest, header: UInt16?) async throws -> OBDQueryResult {
        let index = lock.withLock {
            recordedQueries.append(Query(request: request, header: header))
            return recordedQueries.count - 1
        }
        clock?.advance(microseconds: queryDuration)
        onQuery?(index)
        await Task.yield()
        return try script(request, header, index)
    }

    func close() async { lock.withLock { closes += 1 } }

    var queries: [Query] { lock.withLock { recordedQueries } }
    var closeCount: Int { lock.withLock { closes } }
}

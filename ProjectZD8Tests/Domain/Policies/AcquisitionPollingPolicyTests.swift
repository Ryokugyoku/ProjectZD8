import XCTest
@testable import ProjectZD8

final class AcquisitionPollingPolicyTests: XCTestCase {
    private func pids(fast: Int, slow: Int) -> [SessionPID] {
        let fastPIDs = (0..<fast).map { DriveFlowFixtures.pid($0, OBDPIDRequest(service: 0x01, pid: UInt8($0)), fast: true) }
        let slowPIDs = (0..<slow).map { DriveFlowFixtures.pid(fast + $0, OBDPIDRequest(service: 0x01, pid: UInt8(0x40 + $0))) }
        return fastPIDs + slowPIDs
    }

    func testFastGroupIsRequestedEveryTickBeforeSlowPIDs() {
        let all = pids(fast: 3, slow: 5)
        let policy = AcquisitionPollingPolicy(slowRequestsPerTick: 2)
        for tick in 0..<20 {
            let selected = policy.pidsToPoll(tick: tick, from: all)
            XCTAssertEqual(selected.prefix(3).map(\.ordinal), [0, 1, 2])
            XCTAssertEqual(selected.count, 5)
        }
    }

    func testSlowPIDsAreCoveredRoundRobin() {
        let all = pids(fast: 2, slow: 5)
        let policy = AcquisitionPollingPolicy(slowRequestsPerTick: 2)
        let slowOrdinals = (0..<5).flatMap { tick in policy.pidsToPoll(tick: tick, from: all).filter { !$0.isFastGroup }.map(\.ordinal) }
        // 5 ticks x 2 = 10 slots over 5 PIDs: each exactly twice.
        XCTAssertEqual(Dictionary(grouping: slowOrdinals, by: { $0 }).mapValues(\.count), [2: 2, 3: 2, 4: 2, 5: 2, 6: 2])
    }

    func testSlowCountIsCappedAndNonPolledPIDsAreSkipped() {
        var all = pids(fast: 1, slow: 1)
        all.append(DriveFlowFixtures.pid(2, OBDPIDRequest(service: 0x01, pid: 0x70), enabled: false))
        let selected = AcquisitionPollingPolicy(slowRequestsPerTick: 5).pidsToPoll(tick: 3, from: all)
        XCTAssertEqual(selected.map(\.ordinal), [0, 1])
    }

    func testOnlyFastGroupWhenNoSlowPIDs() {
        let selected = AcquisitionPollingPolicy().pidsToPoll(tick: 7, from: pids(fast: 2, slow: 0))
        XCTAssertEqual(selected.map(\.ordinal), [0, 1])
    }

    func testSlowRequestsPerTickIsAtLeastOne() {
        XCTAssertEqual(AcquisitionPollingPolicy(slowRequestsPerTick: 0).slowRequestsPerTick, 1)
    }
}

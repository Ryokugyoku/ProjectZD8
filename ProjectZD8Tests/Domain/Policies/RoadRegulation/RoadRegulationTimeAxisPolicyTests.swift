import XCTest
@testable import ProjectZD8

/// `RoadRegulationTimeAxisPolicy` が、設計書 §1.5 の規則で単調時計と実時間を選ぶことを検証します。
final class RoadRegulationTimeAxisPolicyTests: XCTestCase {
    private let policy = RoadRegulationTimeAxisPolicy()
    private typealias Fixtures = RoadRegulationTimeSourceFixtures

    /// 責務: 位置のずれ 0 に対して、車速のずれを指定した場合の軸を返します。
    private func axis(speedOffset: Double, locationOffset: Double = 0) -> RoadRegulationTimeAxis {
        policy.select(
            locations: [Fixtures.location(1, monotonicSeconds: 100, offset: locationOffset)],
            speedEntries: [Fixtures.speed(monotonicSeconds: 101, offset: speedOffset)]
        )
    }

    /// 責務: ずれが同じなら単調時計になることを確かめます。
    func testIdenticalOffsetsSelectMonotonic() {
        XCTAssertEqual(axis(speedOffset: 0), .monotonic)
    }

    /// 責務: ずれの最大 − 最小がちょうど 2.0 s なら単調時計、2.01 s なら実時間になることを確かめます。
    func testSpreadBoundaryBetweenTwoAndJustOverTwoSeconds() {
        XCTAssertEqual(axis(speedOffset: 2.0), .monotonic)
        XCTAssertEqual(axis(speedOffset: -2.0), .monotonic)
        XCTAssertEqual(axis(speedOffset: 2.01), .wallClock)
        XCTAssertEqual(axis(speedOffset: -2.01), .wallClock)
    }

    /// 責務: 位置どうしのずれが 2.0 s を超える時、車速があれば実時間になることを確かめます。
    func testLocationSpreadAloneCanForceWallClock() {
        let locations = [
            Fixtures.location(1, monotonicSeconds: 100, offset: 0),
            Fixtures.location(2, monotonicSeconds: 101, offset: 2.01),
        ]
        let speeds = [Fixtures.speed(monotonicSeconds: 100.5, offset: 0)]
        XCTAssertEqual(policy.select(locations: locations, speedEntries: speeds), .wallClock)
        let near = [Fixtures.location(1, monotonicSeconds: 100, offset: 0), Fixtures.location(2, monotonicSeconds: 101, offset: 2.0)]
        XCTAssertEqual(policy.select(locations: near, speedEntries: speeds), .monotonic)
    }

    /// 責務: 車速のうち1つでも単調時刻が無ければ実時間になることを確かめます。
    func testAnySpeedWithoutMonotonicTimeSelectsWallClock() {
        let locations = [Fixtures.location(1, monotonicSeconds: 100)]
        let speeds = [Fixtures.speed(monotonicSeconds: 100), Fixtures.speed(monotonicSeconds: nil, offset: 101)]
        XCTAssertEqual(policy.select(locations: locations, speedEntries: speeds), .wallClock)
        XCTAssertEqual(policy.select(locations: locations, speedEntries: [Fixtures.speed(monotonicSeconds: nil, offset: 100)]), .wallClock)
    }

    /// 責務: 車速が空なら、位置のずれが大きくても単調時計になることを確かめます。
    func testEmptySpeedSelectsMonotonic() {
        let locations = [
            Fixtures.location(1, monotonicSeconds: 100, offset: 0),
            Fixtures.location(2, monotonicSeconds: 101, offset: 50),
        ]
        XCTAssertEqual(policy.select(locations: locations, speedEntries: []), .monotonic)
        XCTAssertEqual(policy.select(locations: [], speedEntries: []), .monotonic)
    }

    /// 責務: 複数の車速のうち最大のずれが基準になる(途中の1点だけ外れても実時間)ことを確かめます。
    func testOneOutlierAmongManySpeedsSelectsWallClock() {
        let locations = [Fixtures.location(1, monotonicSeconds: 100)]
        var speeds = (0..<5).map { Fixtures.speed(monotonicSeconds: 100 + Double($0), offset: 0.5) }
        XCTAssertEqual(policy.select(locations: locations, speedEntries: speeds), .monotonic)
        speeds.append(Fixtures.speed(monotonicSeconds: 106, offset: 3))
        XCTAssertEqual(policy.select(locations: locations, speedEntries: speeds), .wallClock)
    }
}

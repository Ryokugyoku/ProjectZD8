import Foundation
import XCTest
@testable import ProjectZD8

/// 位置と PID の時刻を揃える時計(実時間か単調時計か)の選び方を検証します(設計書 §2.3)。
///
/// 各点の「オフセット」は「observedAt(参照日からの秒)− 単調秒」です。整数秒で組み、誤差を持ち込みません。
@MainActor
final class TelemetryTimeAlignmentPolicyTests: XCTestCase {
    /// 既定(ばらつきの上限 600 s)の検証対象です。
    private let policy = TelemetryTimeAlignmentPolicy()

    /// 時刻の印を作ります。
    ///
    /// 責務: 参照日からの秒と単調時刻の秒から、時刻の印を返します。
    /// - Parameters:
    ///   - reference: observedAt の参照日からの秒。
    ///   - monotonic: 単調時刻の秒。`nil` なら単調時刻なし。
    /// - Returns: 時刻の印。
    private func stamp(_ reference: Double, monotonic: Double?) -> TelemetryClockStamp {
        TelemetryClockStamp(
            observedAt: Date(timeIntervalSinceReferenceDate: reference),
            monotonicNanoseconds: monotonic.map { UInt64($0 * 1_000_000_000) }
        )
    }

    /// 単調時計の時のオフセットを取り出します。
    ///
    /// 責務: 単調時計ならオフセットを、実時間なら `nil` を返します。
    /// - Parameter alignment: 判定の結果。
    /// - Returns: オフセット(秒)。
    private func offset(of alignment: TelemetryTimeAlignment) -> Double? {
        if case .monotonic(let offset) = alignment { return offset }
        return nil
    }

    /// 責務: PID の値が空なら実時間になることを確かめます。
    func testEmptyValuesUseWallClock() {
        let result = policy.alignment(locations: [stamp(10, monotonic: 10)], values: [])

        XCTAssertEqual(result, .wallClock)
    }

    /// 責務: PID の値に単調時刻の無いものが1つでもあれば、ばらつきが小さくても実時間になることを確かめます。
    func testValueWithoutMonotonicUsesWallClock() {
        let values = [stamp(20, monotonic: 20), stamp(21, monotonic: nil), stamp(22, monotonic: 22)]

        let result = policy.alignment(locations: [stamp(10, monotonic: 10)], values: values)

        XCTAssertEqual(result, .wallClock)
    }

    /// 責務: 位置が空なら、PID がすべて単調時刻を持っていても実時間になることを確かめます。
    func testEmptyLocationsUseWallClock() {
        let result = policy.alignment(locations: [], values: [stamp(20, monotonic: 20), stamp(21, monotonic: 21)])

        XCTAssertEqual(result, .wallClock)
    }

    /// 責務: ばらつきが上限の少し内側(599.999 s)なら単調時計になることを確かめます。
    func testSpreadJustInsideLimitUsesMonotonic() {
        let locations = [stamp(10, monotonic: 10)]
        let values = [stamp(619.999, monotonic: 20)]

        let result = policy.alignment(locations: locations, values: values)

        XCTAssertNotNil(offset(of: result))
    }

    /// 責務: ばらつきが上限の少し外側(600.001 s)なら実時間になることを確かめます。
    func testSpreadJustBeyondLimitUsesWallClock() {
        let locations = [stamp(10, monotonic: 10)]
        let values = [stamp(620.001, monotonic: 20)]

        let result = policy.alignment(locations: locations, values: values)

        XCTAssertEqual(result, .wallClock)
    }

    /// 責務: PID だけならばらつきが 0 でも、位置のオフセットが 700 s 離れていれば実時間になることを確かめます。
    func testLocationOffsetsCountTowardSpread() {
        let locations = [stamp(705, monotonic: 5), stamp(6, monotonic: 6)]
        let values = [stamp(20, monotonic: 20), stamp(21, monotonic: 21)]

        let result = policy.alignment(locations: locations, values: values)

        XCTAssertEqual(result, .wallClock)
    }

    /// 責務: 位置どうしのオフセットだけが上限を超えて離れている時も実時間になることを確かめます。
    func testSpreadAmongLocationsOnlyUsesWallClock() {
        let locations = [stamp(0, monotonic: 0), stamp(701, monotonic: 1)]
        let values = [stamp(352, monotonic: 2)]

        let result = policy.alignment(locations: locations, values: values)

        XCTAssertEqual(result, .wallClock)
    }

    /// 責務: 単調時計の時のオフセットが、PID 側のオフセットの中央値(奇数個)になることを確かめます。
    func testOffsetIsMedianOfOddValueCount() {
        let values = [stamp(105, monotonic: 100), stamp(201, monotonic: 200), stamp(303, monotonic: 300)]

        let result = policy.alignment(locations: [stamp(52, monotonic: 50)], values: values)

        XCTAssertEqual(offset(of: result), 3)
    }

    /// 責務: PID 側のオフセットが偶数個なら、下側の中央値になることを確かめます。
    func testOffsetIsLowerMedianOfEvenValueCount() {
        let values = [
            stamp(104, monotonic: 100), stamp(201, monotonic: 200), stamp(303, monotonic: 300), stamp(402, monotonic: 400)
        ]

        let result = policy.alignment(locations: [stamp(53, monotonic: 50)], values: values)

        XCTAssertEqual(offset(of: result), 2)
    }

    /// 責務: オフセットの中央値に位置のオフセットを含めないことを確かめます。
    func testOffsetIgnoresLocationOffsets() {
        let locations = [stamp(110, monotonic: 10), stamp(111, monotonic: 11), stamp(112, monotonic: 12)]
        let values = [stamp(21, monotonic: 20), stamp(32, monotonic: 30), stamp(43, monotonic: 40)]

        let result = policy.alignment(locations: locations, values: values)

        XCTAssertEqual(offset(of: result), 2)
    }

    /// 責務: PID が1件だけなら、その1件のオフセットになることを確かめます。
    func testSingleValueOffset() {
        let result = policy.alignment(locations: [stamp(57, monotonic: 50)], values: [stamp(207, monotonic: 200)])

        XCTAssertEqual(offset(of: result), 7)
    }

    /// 責務: 初期化で渡したばらつきの上限(10 s)が、内側(9.5 s)と外側(10.5 s)の判定に使われることを確かめます。
    func testCustomSpreadLimitIsApplied() {
        let strict = TelemetryTimeAlignmentPolicy(maximumOffsetSpreadSeconds: 10)
        let locations = [stamp(10, monotonic: 10)]

        let inside = strict.alignment(locations: locations, values: [stamp(29.5, monotonic: 20)])
        let outside = strict.alignment(locations: locations, values: [stamp(30.5, monotonic: 20)])

        XCTAssertEqual(offset(of: inside), 9.5)
        XCTAssertEqual(outside, .wallClock)
    }

    /// 責務: 位置に単調時刻の無い点が1つでもあれば、ばらつきが小さくても実時間になることを確かめます。
    func testLocationWithoutMonotonicUsesWallClock() {
        let locations = [stamp(10, monotonic: 10), stamp(11, monotonic: nil)]

        let result = policy.alignment(locations: locations, values: [stamp(20, monotonic: 20)])

        XCTAssertEqual(result, .wallClock)
    }

    /// 責務: ばらつきの上限が NaN なら、ばらつきが 0 でも実時間になることを確かめます。
    func testNaNSpreadLimitUsesWallClock() {
        let invalid = TelemetryTimeAlignmentPolicy(maximumOffsetSpreadSeconds: .nan)

        let result = invalid.alignment(locations: [stamp(10, monotonic: 10)], values: [stamp(20, monotonic: 20)])

        XCTAssertEqual(result, .wallClock)
    }
}

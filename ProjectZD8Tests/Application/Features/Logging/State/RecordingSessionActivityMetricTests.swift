import XCTest
@testable import ProjectZD8

/// 記録中表示の計測値が、観測の有無で値と「未取得」を分けることを検証します。
final class RecordingSessionActivityMetricTests: XCTestCase {
    /// 車速のPIDです。
    private let speed = OBDPIDRequest(service: 0x01, pid: 0x0D)
    /// 回転数のPIDです。
    private let rpm = OBDPIDRequest(service: 0x01, pid: 0x0C)

    /// 観測が無ければ0ではなく未取得です。
    ///
    /// 責務: 空の一覧で `.unavailable` になり、`.value(0)` ではないことを確認します。
    func testEmptySamplesAreUnavailableNotZero() {
        let metric = RecordingSessionActivityMetric(speed, in: [])
        XCTAssertEqual(metric, .unavailable)
        XCTAssertNotEqual(metric, .value(0))
    }

    /// 別PIDの観測しか無ければ未取得です。
    ///
    /// 責務: 一致しない要求は無視されることを確認します。
    func testOtherPIDOnlyIsUnavailable() {
        let samples = [RecordingSessionActivityTestSupport.sample(rpm, value: 900)]
        XCTAssertEqual(RecordingSessionActivityMetric(speed, in: samples), .unavailable)
    }

    /// 一致する観測があればその値です。
    ///
    /// 責務: 複数PIDの中から指定PIDの値を引くことを確認します。
    func testMatchingSampleGivesItsValue() {
        let samples = [
            RecordingSessionActivityTestSupport.sample(rpm, value: 900),
            RecordingSessionActivityTestSupport.sample(speed, value: 42.5)
        ]
        XCTAssertEqual(RecordingSessionActivityMetric(speed, in: samples), .value(42.5))
    }

    /// 値が0の観測は未取得ではなく0として扱います。
    ///
    /// 責務: 境界値0が `.value(0)` になることを確認します。
    func testZeroValueIsValueNotUnavailable() {
        let samples = [RecordingSessionActivityTestSupport.sample(speed, value: 0)]
        XCTAssertEqual(RecordingSessionActivityMetric(speed, in: samples), .value(0))
    }

    /// 未取得の文言キーは仕様の固定値です。
    ///
    /// 責務: 公開定数の値を確認します。
    func testUnavailableKey() {
        XCTAssertEqual(RecordingSessionActivityMetric.unavailableKey, "live_activity.metric.unavailable")
    }
}

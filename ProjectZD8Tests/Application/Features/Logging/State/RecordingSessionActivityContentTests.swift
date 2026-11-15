import XCTest
@testable import ProjectZD8

/// 記録中表示の内容が、取得状態・車両・受信件数・開始時刻をそのまま載せることを検証します。
@MainActor
final class RecordingSessionActivityContentTests: XCTestCase {
    /// 車速の要求(PID 0D)です。
    private let speed = OBDPIDRequest(service: 0x01, pid: 0x0D)
    /// 回転数の要求(PID 0C)です。
    private let rpm = OBDPIDRequest(service: 0x01, pid: 0x0C)
    /// スロットル開度の要求(PID 11)です。
    private let throttle = OBDPIDRequest(service: 0x01, pid: 0x11)
    /// 記録開始時刻です。
    private let startedAt = Date(timeIntervalSince1970: 1_234)

    /// 内容を生成します。
    ///
    /// 責務: 車両名と状態から表示内容を作ります。
    private func content(_ state: LiveTelemetryState, name: String? = "BRZ", photo: String? = nil) -> RecordingSessionActivityContent {
        RecordingSessionActivityContent(telemetry: state, vehicleName: name, startedAt: startedAt, vehiclePhotoFileName: photo)
    }

    /// 3指標の値と受信件数・開始時刻・車両名・写真名がそのまま載ります。
    ///
    /// 責務: すべての値がある場合の各欄を確認します。
    func testAllFieldsAreCarried() {
        let samples = [
            RecordingSessionActivityTestSupport.sample(speed, value: 60),
            RecordingSessionActivityTestSupport.sample(rpm, value: 2_500),
            RecordingSessionActivityTestSupport.sample(throttle, value: 12.5)
        ]
        let result = content(
            RecordingSessionActivityTestSupport.state(.loaded, samples: samples, receivedCount: 77), photo: "p.jpg"
        )
        XCTAssertEqual(result.vehicle, .named("BRZ"))
        XCTAssertEqual(result.vehicleSpeed, .value(60))
        XCTAssertEqual(result.engineSpeed, .value(2_500))
        XCTAssertEqual(result.throttlePosition, .value(12.5))
        XCTAssertEqual(result.receivedResponseCount, 77)
        XCTAssertEqual(result.startedAt, startedAt)
        XCTAssertEqual(result.vehiclePhotoFileName, "p.jpg")
        XCTAssertEqual(result.statusKey, "live_activity.status.recording")
        XCTAssertEqual(result.statusTone, .normal)
    }

    /// 車速だけ無ければ車速のみ未取得で、他は値のままです。
    ///
    /// 責務: 車速の未取得を確認します。
    func testMissingSpeedOnlyIsUnavailable() {
        let samples = [RecordingSessionActivityTestSupport.sample(rpm, value: 1), RecordingSessionActivityTestSupport.sample(throttle, value: 2)]
        let result = content(RecordingSessionActivityTestSupport.state(.loaded, samples: samples))
        XCTAssertEqual(result.vehicleSpeed, .unavailable)
        XCTAssertEqual(result.engineSpeed, .value(1))
        XCTAssertEqual(result.throttlePosition, .value(2))
    }

    /// 回転数だけ無ければ回転数のみ未取得です。
    ///
    /// 責務: 回転数の未取得を確認します。
    func testMissingEngineSpeedOnlyIsUnavailable() {
        let samples = [RecordingSessionActivityTestSupport.sample(speed, value: 1), RecordingSessionActivityTestSupport.sample(throttle, value: 2)]
        let result = content(RecordingSessionActivityTestSupport.state(.loaded, samples: samples))
        XCTAssertEqual(result.vehicleSpeed, .value(1))
        XCTAssertEqual(result.engineSpeed, .unavailable)
        XCTAssertEqual(result.throttlePosition, .value(2))
    }

    /// スロットル開度だけ無ければ開度のみ未取得です。
    ///
    /// 責務: スロットル開度の未取得を確認します。
    func testMissingThrottleOnlyIsUnavailable() {
        let samples = [RecordingSessionActivityTestSupport.sample(speed, value: 1), RecordingSessionActivityTestSupport.sample(rpm, value: 2)]
        let result = content(RecordingSessionActivityTestSupport.state(.loaded, samples: samples))
        XCTAssertEqual(result.vehicleSpeed, .value(1))
        XCTAssertEqual(result.engineSpeed, .value(2))
        XCTAssertEqual(result.throttlePosition, .unavailable)
    }

    /// 未登録車両と、警告の状態の強調です。
    ///
    /// 責務: 車両名なしが未登録になり、警告段階で警告色になることを確認します。
    func testUnregisteredVehicleAndWarningTone() {
        let result = content(RecordingSessionActivityTestSupport.state(.failed), name: nil)
        XCTAssertEqual(result.vehicle, .unregistered)
        XCTAssertEqual(result.statusTone, .warning)
        XCTAssertNil(result.vehiclePhotoFileName)
        XCTAssertEqual(result.vehicleSpeed, .unavailable)
    }

    /// 状態が同じで受信件数だけ違う内容は等しくありません。
    ///
    /// 責務: 受信件数が内容の同一性に含まれることを確認します。
    func testReceivedCountParticipatesInEquality() {
        let first = content(RecordingSessionActivityTestSupport.state(.loaded, receivedCount: 1))
        let second = content(RecordingSessionActivityTestSupport.state(.loaded, receivedCount: 2))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, content(RecordingSessionActivityTestSupport.state(.loaded, receivedCount: 1)))
    }
}

import Foundation
import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityContentStateMapper` が Application の表示内容を同じ意味の `ContentState` へ写すことを、分岐ごとに検証します。
///
/// 仕様: U5 受け入れ条件 10・13(B14)。
@MainActor
final class RecordingSessionActivityContentStateMapperTests: XCTestCase {
    /// 検証対象です。
    private let mapper = RecordingSessionActivityContentStateMapper()

    /// 表示内容を作ります。
    ///
    /// 責務: 取得段階・車速・車両名・写真名から1件の表示内容を作ります(他の計測値は未取得)。
    private func content(
        phase: LiveTelemetryState.Phase, speed: Double?, vehicleName: String?, photo: String?
    ) -> RecordingSessionActivityContent {
        var telemetry = LiveTelemetryState()
        telemetry.phase = phase
        if let speed {
            telemetry.samples = [OBDPIDSample(
                request: RecordingSessionActivityContent.vehicleSpeedRequest,
                nameKey: "speed", value: speed, unit: "km/h", observedAt: Date(timeIntervalSince1970: 0)
            )]
        }
        return RecordingSessionActivityContent(
            telemetry: telemetry, vehicleName: vehicleName, startedAt: Date(timeIntervalSince1970: 500), vehiclePhotoFileName: photo
        )
    }

    /// 名称あり・通常の強調・取得済みの車速・写真ありの内容を、同じ意味の値へ写します。
    ///
    /// 責務: 車両名・状態キー・強調・3つの計測値・件数・開始時刻・写真名が対応することを確認します。
    func testMapsNamedNormalWithValues() {
        let source = content(phase: .loaded, speed: 42, vehicleName: "BRZ", photo: "p.jpg")
        let state = mapper.contentState(from: source)
        XCTAssertEqual(state.vehicle, .named("BRZ"))
        XCTAssertEqual(state.statusKey, source.statusKey)
        XCTAssertEqual(state.statusTone, .normal)
        XCTAssertEqual(state.vehicleSpeed, .value(42))
        XCTAssertEqual(state.engineSpeed, .unavailable)
        XCTAssertEqual(state.throttlePosition, .unavailable)
        XCTAssertEqual(state.receivedResponseCount, source.receivedResponseCount)
        XCTAssertEqual(state.startedAt, Date(timeIntervalSince1970: 500))
        XCTAssertEqual(state.vehiclePhotoFileName, "p.jpg")
    }

    /// 未登録・警告の強調・未取得・写真なしの内容を、同じ意味の値へ写します。
    ///
    /// 責務: 失敗段階の内容で `.unregistered`・`.warning`・`.unavailable`・写真名 `nil` になることを確認します。
    func testMapsUnregisteredWarningUnavailable() {
        let source = content(phase: .failed, speed: nil, vehicleName: nil, photo: nil)
        XCTAssertEqual(source.statusTone, .warning, "前提: 失敗は警告の強調")
        let state = mapper.contentState(from: source)
        XCTAssertEqual(state.vehicle, .unregistered)
        XCTAssertEqual(state.statusTone, .warning)
        XCTAssertEqual(state.statusKey, "live_activity.status.failed")
        XCTAssertEqual(state.vehicleSpeed, .unavailable)
        XCTAssertNil(state.vehiclePhotoFileName)
    }
}

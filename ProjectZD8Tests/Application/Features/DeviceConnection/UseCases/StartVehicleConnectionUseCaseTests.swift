import XCTest
@testable import ProjectZD8

/// HOME接続開始が車両識別とTelemetry開始へ展開されることを検証します。
@MainActor
final class StartVehicleConnectionUseCaseTests: XCTestCase {
    /// 同じOBD終端を識別とTelemetryへ順番に通知します。
    ///
    /// 責務: 接続開始ユースケースが必要な2件のApplication通知を欠落なく発行することを確認します。
    func testExecuteStartsIdentificationThenLiveTelemetry() {
        var events: [String] = []
        let endpoint = OBDConnectionEndpoint(
            transport: .serial,
            systemIdentifier: "projectzd8://test",
            displayName: "Test"
        )
        let useCase = StartVehicleConnectionUseCase(
            identifyVehicle: { received in
                XCTAssertEqual(received, endpoint)
                events.append("identify")
            },
            startLiveTelemetry: { received in
                XCTAssertEqual(received, endpoint)
                events.append("telemetry")
            }
        )

        useCase.execute(endpoint: endpoint)

        XCTAssertEqual(events, ["identify", "telemetry"])
    }
}

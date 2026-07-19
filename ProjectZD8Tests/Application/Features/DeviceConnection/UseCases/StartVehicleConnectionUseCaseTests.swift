import XCTest
@testable import ProjectZD8

/// HOME接続開始がセッション、車両識別、Telemetry開始へ展開されることを検証します。
@MainActor
final class StartVehicleConnectionUseCaseTests: XCTestCase {
    /// セッション開始後に同じOBD終端を識別とTelemetryへ順番に通知します。
    ///
    /// 責務: 接続開始ユースケースが必要な3件のApplication通知を欠落なく発行することを確認します。
    func testExecuteStartsSessionThenIdentificationThenLiveTelemetry() {
        var events: [String] = []
        let endpoint = OBDConnectionEndpoint(
            transport: .serial,
            systemIdentifier: "projectzd8://test",
            displayName: "Test"
        )
        let useCase = StartVehicleConnectionUseCase(
            startConnectionSession: { events.append("session") },
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

        XCTAssertEqual(events, ["session", "identify", "telemetry"])
    }
}

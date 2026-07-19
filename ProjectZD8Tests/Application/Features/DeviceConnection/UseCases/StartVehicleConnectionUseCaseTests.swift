import XCTest
@testable import ProjectZD8

/// HOME接続開始がセッションと車両識別へ展開されることを検証します。
@MainActor
final class StartVehicleConnectionUseCaseTests: XCTestCase {
    /// セッション開始後に同じOBD終端を車両識別へ通知します。
    ///
    /// 責務: PID監視を車両確定前に開始せず必要な2件のApplication通知を発行することを確認します。
    func testExecuteStartsSessionThenIdentification() {
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
            }
        )

        useCase.execute(endpoint: endpoint)

        XCTAssertEqual(events, ["session", "identify"])
    }
}

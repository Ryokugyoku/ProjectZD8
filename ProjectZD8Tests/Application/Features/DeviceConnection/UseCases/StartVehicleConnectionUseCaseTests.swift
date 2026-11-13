import XCTest
@testable import ProjectZD8

/// HOME接続開始が車両確定前の識別だけへ展開されることを検証します。
@MainActor
final class StartVehicleConnectionUseCaseTests: XCTestCase {
    /// 接続セッションを先行開始せず同じOBD終端を車両識別へ通知します。
    ///
    /// 責務: HOME接続要求が車両識別通知だけを発行することを確認します。
    func testExecuteStartsIdentification() {
        var receivedEndpoint: OBDConnectionEndpoint?
        let endpoint = OBDConnectionEndpoint(
            transport: .serial,
            systemIdentifier: "projectzd8://test",
            displayName: "Test"
        )
        let useCase = StartVehicleConnectionUseCase(
            identifyVehicle: { receivedEndpoint = $0 }
        )

        useCase.execute(endpoint: endpoint)

        XCTAssertEqual(receivedEndpoint, endpoint)
    }
}

import XCTest
@testable import ProjectZD8

/// `VehicleOffDetectionDelayPreferenceUseCase` が保存ポートへ読み書きを委ねることを検証します。
@MainActor
final class VehicleOffDetectionDelayPreferenceUseCaseTests: XCTestCase {
    /// 読み出しは保存ポートの値をそのまま返します。
    ///
    /// 責務: 4つの選択肢それぞれで `load()` がポートの値を返すことを確認します。
    func testLoadReturnsPortValue() {
        for delay in VehicleOffDetectionDelay.allCases {
            let port = VehicleOffDetectionDelayPreferencePortFake(initial: delay)
            let useCase = VehicleOffDetectionDelayPreferenceUseCase(preferencePort: port)

            XCTAssertEqual(useCase.load(), delay)
            XCTAssertEqual(port.loadCount, 1)
        }
    }

    /// 保存は選択された値を1回だけポートへ渡します。
    ///
    /// 責務: `save(_:)` が値を変えずに1回保存することと、保存後の読み出しに反映されることを確認します。
    func testSaveDelegatesOnceToPort() {
        let port = VehicleOffDetectionDelayPreferencePortFake()
        let useCase = VehicleOffDetectionDelayPreferenceUseCase(preferencePort: port)

        useCase.save(.seconds180)

        XCTAssertEqual(port.saved, [.seconds180])
        XCTAssertEqual(useCase.load(), .seconds180)
    }

    /// 読み出しだけでは保存しません。
    ///
    /// 責務: `load()` が副作用で保存しないことを確認します。
    func testLoadDoesNotSave() {
        let port = VehicleOffDetectionDelayPreferencePortFake(initial: .seconds60)

        _ = VehicleOffDetectionDelayPreferenceUseCase(preferencePort: port).load()

        XCTAssertEqual(port.saved, [])
    }
}

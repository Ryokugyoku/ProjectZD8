import XCTest
@testable import ProjectZD8

/// `VehicleOffDetectionDelayModel` の初期表示と、選択による保存・表示の更新を検証します。
@MainActor
final class VehicleOffDetectionDelayModelTests: XCTestCase {
    /// 初期の section は保存済みの値の選択状態です。
    ///
    /// 責務: 4つの保存値それぞれで、生成直後の `section.selectedDelay` が保存値になることを確認します。
    func testInitialSectionReflectsStoredValue() {
        for delay in VehicleOffDetectionDelay.allCases {
            let port = VehicleOffDetectionDelayPreferencePortFake(initial: delay)

            let model = makeModel(port: port)

            XCTAssertEqual(model.section.selectedDelay, delay)
            XCTAssertEqual(port.saved, [], "生成だけでは保存しない")
        }
    }

    /// 選択すると保存され、section が選んだ値に更新されます。
    ///
    /// 責務: 4つの選択肢それぞれで `send(.delaySelected)` の保存と表示の更新を確認します。
    func testSelectingSavesAndUpdatesSection() {
        for delay in VehicleOffDetectionDelay.allCases {
            let port = VehicleOffDetectionDelayPreferencePortFake(initial: .seconds30)
            let model = makeModel(port: port)

            model.send(.delaySelected(delay))

            XCTAssertEqual(port.saved, [delay])
            XCTAssertEqual(model.section.selectedDelay, delay)
            XCTAssertEqual(port.load(), delay)
        }
    }

    /// 続けて選ぶと、保存は選んだ順で、表示は最後の選択です。
    ///
    /// 責務: 連続した選択の保存順と最終表示を確認します。
    func testConsecutiveSelectionsKeepOrderAndLastWins() {
        let port = VehicleOffDetectionDelayPreferencePortFake()
        let model = makeModel(port: port)

        model.send(.delaySelected(.seconds10))
        model.send(.delaySelected(.seconds180))

        XCTAssertEqual(port.saved, [.seconds10, .seconds180])
        XCTAssertEqual(model.section.selectedDelay, .seconds180)
    }

    /// 保存ポートを使うモデルを生成します。
    ///
    /// 責務: テスト用のモデルを組み立てます。
    /// - Parameter port: 保存ポートのフェイク。
    /// - Returns: モデル。
    private func makeModel(port: VehicleOffDetectionDelayPreferencePortFake) -> VehicleOffDetectionDelayModel {
        VehicleOffDetectionDelayModel(preference: VehicleOffDetectionDelayPreferenceUseCase(preferencePort: port))
    }
}

import XCTest
@testable import ProjectZD8

/// `AutomaticRecordingPreferenceUseCase` の読込と保存を検証します。
@MainActor
final class AutomaticRecordingPreferenceUseCaseTests: XCTestCase {
    /// 読込は保存境界の値をそのまま返します。
    ///
    /// 責務: 保存値がオン・オフのそれぞれで同じ値が返ることを確認します。
    func testLoadReturnsStoredValue() {
        for stored in [true, false] {
            let port = AutomaticRecordingPreferenceFake(isEnabled: stored)
            let useCase = AutomaticRecordingPreferenceUseCase(preferencePort: port)
            XCTAssertEqual(useCase.load(), stored)
            XCTAssertEqual(port.loadCount, 1)
        }
    }

    /// 保存は渡した値を保存境界へ1回渡し、以後の読込に反映されます。
    ///
    /// 責務: オン・オフの保存が順に保存境界へ届き、読込が最後の保存値を返すことを確認します。
    func testSavePersistsValueAndIsReflectedInLoad() {
        let port = AutomaticRecordingPreferenceFake(isEnabled: false)
        let useCase = AutomaticRecordingPreferenceUseCase(preferencePort: port)

        useCase.save(true)
        XCTAssertEqual(port.savedValues, [true])
        XCTAssertTrue(useCase.load())

        useCase.save(false)
        XCTAssertEqual(port.savedValues, [true, false])
        XCTAssertFalse(useCase.load())
    }
}

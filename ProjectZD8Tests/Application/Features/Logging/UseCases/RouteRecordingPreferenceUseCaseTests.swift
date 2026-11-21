import XCTest
@testable import ProjectZD8

/// `RouteRecordingPreferenceUseCase` の読込と保存を検証します。
@MainActor
final class RouteRecordingPreferenceUseCaseTests: XCTestCase {
    /// 読込は保存先の値をそのまま返します。
    ///
    /// 責務: 保存値がオン・オフのそれぞれで同じ値が返り、保存先を1回読むことを確認します。
    func testLoadReturnsStoredValue() {
        for stored in [true, false] {
            let store = RouteRecordingPreferenceStoreFake(isEnabled: stored)
            let useCase = RouteRecordingPreferenceUseCase(preferencePort: store)
            XCTAssertEqual(useCase.load(), stored)
            XCTAssertEqual(store.loadCount, 1)
        }
    }

    /// 保存は渡した値を保存先へ順に渡し、以後の読込に反映されます。
    ///
    /// 責務: オン・オフの保存が保存先へ届き、読込が最後の保存値を返すことを確認します。
    func testSavePassesValueToStore() {
        let store = RouteRecordingPreferenceStoreFake(isEnabled: false)
        let useCase = RouteRecordingPreferenceUseCase(preferencePort: store)

        useCase.save(true)
        XCTAssertEqual(store.savedValues, [true])
        XCTAssertTrue(useCase.load())

        useCase.save(false)
        XCTAssertEqual(store.savedValues, [true, false])
        XCTAssertFalse(useCase.load())
    }
}

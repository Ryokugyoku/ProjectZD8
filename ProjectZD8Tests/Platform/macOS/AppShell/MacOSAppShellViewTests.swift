#if os(macOS)
import XCTest
@testable import ProjectZD8

/// macOS AppShellが車両識別結果に応じて自動遷移する規則を検証します。
final class MacOSAppShellViewTests: XCTestCase {
    /// 登録済み車両への接続準備完了ではGarageへ遷移しないことを検証します。
    ///
    /// 責務: 登録済み車両の接続段階が自動遷移先を生成しないことを確認します。
    func testRegisteredVehicleDoesNotNavigateToGarage() {
        let destination = MacOSAppShellView.destination(forVehicleManagementPhase: .readyToConnect)

        XCTAssertNil(destination)
    }

    /// 未登録車両の識別確認ではGarageへ遷移することを検証します。
    ///
    /// 責務: 新規登録確認段階をGarage遷移へ変換することを確認します。
    func testUnregisteredVehicleNavigatesToGarage() {
        let destination = MacOSAppShellView.destination(forVehicleManagementPhase: .confirmingIdentification)

        XCTAssertEqual(destination, .garage)
    }

    /// 識別失敗では再試行操作を提供するGarageへ遷移することを検証します。
    ///
    /// 責務: 車両識別失敗段階をGarage遷移へ変換することを確認します。
    func testIdentificationFailureNavigatesToGarage() {
        let destination = MacOSAppShellView.destination(forVehicleManagementPhase: .failed)

        XCTAssertEqual(destination, .garage)
    }
}
#endif

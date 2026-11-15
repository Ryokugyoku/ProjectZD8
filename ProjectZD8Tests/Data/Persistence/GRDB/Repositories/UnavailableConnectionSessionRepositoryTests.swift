import Foundation
import XCTest
@testable import ProjectZD8

/// `UnavailableConnectionSessionRepository` の観測VIN操作が空結果へ潰れず利用不能を返すことを検証します。
final class UnavailableConnectionSessionRepositoryTests: XCTestCase {
    /// 未紐付けセッションの照会は空配列ではなく `unavailable` で失敗します。
    ///
    /// 責務: DB準備不可時の照会が該当なしと区別できる型付きエラーになることを確認します。
    func testUnassignedSessionsWithObservedVINThrowsUnavailable() {
        assertThrowsError(ConnectionSessionRepositoryError.unavailable) {
            _ = try UnavailableConnectionSessionRepository().unassignedSessionsWithObservedVIN(for: "account")
        }
    }

    /// VINによる車両紐付けは0件ではなく `unavailable` で失敗します。
    ///
    /// 責務: DB準備不可時の紐付けが一致なしと区別できる型付きエラーになることを確認します。
    func testAssignVehicleThrowsUnavailable() {
        let vehicle = ConnectionSessionVehicle(id: VehicleID(), name: "BRZ", displayIdentifier: "ZD8")

        assertThrowsError(ConnectionSessionRepositoryError.unavailable) {
            _ = try UnavailableConnectionSessionRepository().assignVehicle(
                vehicle,
                toUnassignedSessionsWithObservedVIN: "JF1ZD8ABC12345678",
                for: "account"
            )
        }
    }
}

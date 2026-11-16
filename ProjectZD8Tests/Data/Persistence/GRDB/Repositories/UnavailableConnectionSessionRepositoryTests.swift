import Foundation
import XCTest
@testable import ProjectZD8

/// DB準備不可時のセッションRepositoryが、観測VIN操作とプロセス復帰の操作を空結果へ潰さず、明示的な利用不能として失敗させることを検証します。
final class UnavailableConnectionSessionRepositoryTests: XCTestCase {
    /// 中断batchの確定と中断セッションの終了は、どちらも利用不能で失敗します。
    ///
    /// 責務: プロセス復帰の2つの操作が空の成功を返さないことを確認します。
    func testInterruptedAcquisitionOperationsThrowUnavailable() {
        let repository = UnavailableConnectionSessionRepository()
        let session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 1))

        XCTAssertThrowsError(try repository.sealInterruptedBatches(for: session.id, completedAt: Date(timeIntervalSince1970: 2))) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .unavailable)
        }
        XCTAssertThrowsError(try repository.finishInterruptedSessionAcquisition(session, endedAt: Date(timeIntervalSince1970: 2))) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .unavailable)
        }
    }

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

    /// 車両不明ログの照会は空配列ではなく `unavailable` で失敗します。
    ///
    /// 責務: DB準備不可時の照会が「該当なし」と区別できる型付きエラーになることを確認します(U4 受け入れ条件 15)。
    func testVehicleUnknownSessionsThrowsUnavailable() {
        assertThrowsError(ConnectionSessionRepositoryError.unavailable) {
            _ = try UnavailableConnectionSessionRepository().vehicleUnknownSessions(for: "account")
        }
    }

    /// 車両不明ログへの紐付けは0件ではなく `unavailable` で失敗します。
    ///
    /// 責務: 空でないID列・空のID列のどちらでも、紐付けが「対象なし」と区別できる型付きエラーになることを確認します(U4 受け入れ条件 15)。
    func testAssignVehicleToVehicleUnknownSessionsThrowsUnavailable() {
        let vehicle = ConnectionSessionVehicle(id: VehicleID(), name: "BRZ", displayIdentifier: "ZD8")
        for ids: [ConnectionSessionID] in [[ConnectionSessionID()], []] {
            assertThrowsError(ConnectionSessionRepositoryError.unavailable) {
                _ = try UnavailableConnectionSessionRepository().assignVehicle(vehicle, toVehicleUnknownSessions: ids, for: "account")
            }
        }
    }
}

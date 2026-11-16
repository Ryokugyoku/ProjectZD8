import Foundation
import XCTest
@testable import ProjectZD8

/// `VehicleUnknownSessionAssignmentState` の紐付けの可否・選択の判定・車両が無い時の案内を、分岐と境界で検証します。
///
/// 仕様: U4 受け入れ条件 12・17(ログを1件以上選び、登録済みの車両を選んだ時だけ紐付けられる)。
final class VehicleUnknownSessionAssignmentStateTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = VehicleUnknownSessionFixture

    /// 選択を指定した状態を作ります。
    ///
    /// 責務: 2件の候補のうち指定したログと車両を選んだ状態を返します。
    /// - Parameters:
    ///   - selectedCount: 選ぶログの件数(先頭から)。
    ///   - vehicleID: 選んだ車両のID。
    /// - Returns: 状態。
    private func state(selectedCount: Int, vehicleID: VehicleID?) -> VehicleUnknownSessionAssignmentState {
        let sessions = [F.session(startedAt: 200), F.session(startedAt: 100)]
        return VehicleUnknownSessionAssignmentState(
            isPresented: true,
            sessions: sessions,
            selectedSessionIDs: Set(sessions.prefix(selectedCount).map(\.id)),
            selectedVehicleID: vehicleID
        )
    }

    /// 既定の状態は非表示・候補なし・選択なし・失敗なしです。
    ///
    /// 責務: 初期値を確認します。
    func testDefaultState() {
        let state = VehicleUnknownSessionAssignmentState()
        XCTAssertFalse(state.isPresented)
        XCTAssertEqual(state.sessions, [])
        XCTAssertEqual(state.selectedSessionIDs, [])
        XCTAssertNil(state.selectedVehicleID)
        XCTAssertNil(state.failureKey)
    }

    /// ログを1件以上選び、選んだ車両が候補にある時だけ紐付けられます。
    ///
    /// 責務: ログ1件・2件と候補の車両で `true` になることを確認します。
    func testCanAssignWithSelectedSessionsAndCandidateVehicle() {
        let vehicles = [F.otherVehicle, F.vehicle]
        XCTAssertTrue(state(selectedCount: 1, vehicleID: F.vehicle.id).canAssign(among: vehicles))
        XCTAssertTrue(state(selectedCount: 2, vehicleID: F.vehicle.id).canAssign(among: vehicles))
    }

    /// ログを選んでいない・車両を選んでいない・選んだ車両が候補に無い時は紐付けられません。
    ///
    /// 責務: 各条件の欠けで `false` になり、候補が空でも `false` であることを確認します。
    func testCannotAssignWhenSelectionIsIncomplete() {
        let vehicles = [F.vehicle]
        XCTAssertFalse(state(selectedCount: 0, vehicleID: F.vehicle.id).canAssign(among: vehicles), "ログ0件")
        XCTAssertFalse(state(selectedCount: 1, vehicleID: nil).canAssign(among: vehicles), "車両なし")
        XCTAssertFalse(state(selectedCount: 1, vehicleID: F.otherVehicle.id).canAssign(among: vehicles), "候補に無い車両")
        XCTAssertFalse(state(selectedCount: 1, vehicleID: F.vehicle.id).canAssign(among: []), "候補が空")
    }

    /// 選択集合に含まれるログだけが選ばれていると判定します。
    ///
    /// 責務: 選んだログで `true`、選んでいない候補と候補外のIDで `false` であることを確認します。
    func testIsSelected() {
        let state = state(selectedCount: 1, vehicleID: nil)
        XCTAssertTrue(state.isSelected(state.sessions[0].id))
        XCTAssertFalse(state.isSelected(state.sessions[1].id))
        XCTAssertFalse(state.isSelected(ConnectionSessionID()))
    }

    /// 候補の車両が無い時だけ、車両登録の案内を返します。
    ///
    /// 責務: 候補0台で案内キー、1台以上で `nil` であることを確認します。
    func testNoVehicleMessageKey() {
        let state = VehicleUnknownSessionAssignmentState()
        XCTAssertEqual(state.noVehicleMessageKey(among: []), "vehicle_unknown.assignment.no_vehicles")
        XCTAssertNil(state.noVehicleMessageKey(among: [F.vehicle]))
        XCTAssertNil(state.noVehicleMessageKey(among: [F.vehicle, F.otherVehicle]))
    }
}

import Foundation
import XCTest
@testable import ProjectZD8

/// 車両プロフィールの登録確認・観測VIN登録・登録取消・編集開始・編集終了の状態遷移を検証します。
@MainActor
final class VehicleProfileEditingFlowTests: XCTestCase {
    /// 検証対象の遷移処理です。
    private let flow = VehicleProfileEditingFlow()

    /// 指定した取得フィールドを持つ識別観測を生成します。
    ///
    /// 責務: VINまたは非VIN識別子と、メーカー・エンジン型式のフィールドを持つ観測を作ります。
    /// - Parameters:
    ///   - vin: 取得したVIN。
    ///   - obdIdentifier: VINと確認できない識別子。
    ///   - fields: 観測フィールドの `id` と値の組。
    /// - Returns: 生成した識別観測。
    private func snapshot(
        vin: String? = nil,
        obdIdentifier: String? = nil,
        fields: [(id: String, value: String)] = []
    ) -> VehicleIdentificationSnapshot {
        VehicleIdentificationSnapshot(
            vin: vin,
            obdIdentifier: obdIdentifier,
            fields: fields.map { .init(id: $0.id, label: $0.id, value: $0.value, source: "ECU") },
            observedAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// 確認待ちの識別観測を持つ状態を生成します。
    ///
    /// 責務: 登録確認の段階で観測を保持している状態を作ります。
    /// - Parameter pending: 保持する識別観測。
    /// - Returns: 生成した状態。
    private func confirmingState(_ pending: VehicleIdentificationSnapshot?) -> VehicleManagementState {
        var state = VehicleManagementState()
        state.pendingIdentification = pending
        state.phase = .confirmingIdentification
        return state
    }

    /// 操作を適用した結果の状態を返します。
    ///
    /// 責務: 与えた状態へ1件の操作を適用した後の状態を返します。
    /// - Parameters:
    ///   - action: 適用する操作。
    ///   - state: 適用前の状態。
    /// - Returns: 適用後の状態。
    private func applied(_ action: VehicleManagementAction, to state: VehicleManagementState) -> VehicleManagementState {
        var result = state
        flow.apply(action, to: &result)
        return result
    }

    /// VIN付きの観測を確認すると、メーカーとエンジン型式を引き継いだ新規プロフィールで登録入力へ進みます。
    ///
    /// 責務: VINと全フィールドを持つ観測から、編集用プロフィールと `.registering` が作られることを確認します。
    func testIdentificationConfirmedWithVINBuildsProfileFromFields() throws {
        let observed = snapshot(vin: "JF1ZD8A11P9000001", fields: [("manufacturer", "SUBARU"), ("engineModel", "FA24")])
        let result = applied(.identificationConfirmed, to: confirmingState(observed))
        let profile = try XCTUnwrap(result.editingVehicle)
        XCTAssertEqual(result.phase, .registering)
        XCTAssertEqual(profile.vin, "JF1ZD8A11P9000001")
        XCTAssertNil(profile.obdIdentifier)
        XCTAssertEqual(profile.name, "SUBARU")
        XCTAssertEqual(profile.manufacturer, "SUBARU")
        XCTAssertEqual(profile.engineModel, "FA24")
        XCTAssertFalse(profile.isDefault)
        XCTAssertEqual(result.pendingIdentification, observed)
    }

    /// VINがなく非VIN識別子だけの観測でも、VINを空にして登録入力へ進みます。
    ///
    /// 責務: 非VIN識別子だけの観測が、VIN空・識別子ありのプロフィールになることを確認します。
    func testIdentificationConfirmedWithOnlyOBDIdentifierKeepsIdentifier() throws {
        let result = applied(.identificationConfirmed, to: confirmingState(snapshot(obdIdentifier: "OBD-123")))
        let profile = try XCTUnwrap(result.editingVehicle)
        XCTAssertEqual(result.phase, .registering)
        XCTAssertEqual(profile.vin, "")
        XCTAssertEqual(profile.obdIdentifier, "OBD-123")
    }

    /// メーカーなど対応フィールドが無い、または空なら、名前・メーカー・型式は空になります。
    ///
    /// 責務: フィールド欠落と空文字の両方で、名称が空のまま登録入力へ進むことを確認します。
    func testIdentificationConfirmedWithMissingOrEmptyFieldsLeavesNamesEmpty() throws {
        let missing = applied(.identificationConfirmed, to: confirmingState(snapshot(vin: "V1")))
        let empty = applied(
            .identificationConfirmed,
            to: confirmingState(snapshot(vin: "V1", fields: [("manufacturer", ""), ("engineModel", "")]))
        )
        for result in [missing, empty] {
            let profile = try XCTUnwrap(result.editingVehicle)
            XCTAssertEqual(profile.name, "")
            XCTAssertEqual(profile.manufacturer, "")
            XCTAssertEqual(profile.engineModel, "")
            XCTAssertEqual(result.phase, .registering)
        }
    }

    /// 保持中の観測が無い、またはVINも識別子も無い観測なら、状態を変えません。
    ///
    /// 責務: 登録確認の前提を満たさない2つの場合で、状態が完全に同じままであることを確認します。
    func testIdentificationConfirmedWithoutUsableObservationDoesNothing() {
        let noPending = confirmingState(nil)
        let noIdentifier = confirmingState(snapshot(fields: [("manufacturer", "SUBARU")]))
        XCTAssertEqual(applied(.identificationConfirmed, to: noPending), noPending)
        XCTAssertEqual(applied(.identificationConfirmed, to: noIdentifier), noIdentifier)
    }

    /// 操作待ち・接続待ち・失敗の各段階で観測VINを受けると、前後の空白を除いたVINで登録入力へ進みます。
    ///
    /// 責務: 受け付ける3段階で、観測と失敗文言を消し、空欄の新規プロフィールで `.registering` になることを確認します。
    func testObservedVINRegistrationStartsFromAcceptedPhases() throws {
        for phase in [VehicleManagementState.Phase.idle, .readyToConnect, .failed] {
            var state = confirmingState(snapshot(vin: "OLD"))
            state.phase = phase
            state.failureKey = "garage.error.timeout"
            let result = applied(.observedVINRegistrationRequested("  JF1ZD8A11P9000001\n"), to: state)
            let profile = try XCTUnwrap(result.editingVehicle, "\(phase)")
            XCTAssertEqual(result.phase, .registering, "\(phase)")
            XCTAssertEqual(profile.vin, "JF1ZD8A11P9000001", "\(phase)")
            XCTAssertNil(profile.obdIdentifier, "\(phase)")
            XCTAssertEqual([profile.name, profile.manufacturer, profile.engineModel], ["", "", ""], "\(phase)")
            XCTAssertNil(result.pendingIdentification, "\(phase)")
            XCTAssertNil(result.failureKey, "\(phase)")
        }
    }

    /// 受け付けない段階では、観測VINを受けても状態を変えません。
    ///
    /// 責務: 読込中・識別中・登録確認中・登録中・編集中で、状態が完全に同じままであることを確認します。
    func testObservedVINRegistrationIgnoredInOtherPhases() {
        for phase in [VehicleManagementState.Phase.loading, .identifying, .confirmingIdentification, .registering, .editing] {
            var state = VehicleManagementState()
            state.phase = phase
            XCTAssertEqual(applied(.observedVINRegistrationRequested("JF1ZD8A11P9000001"), to: state), state, "\(phase)")
        }
    }

    /// 空文字や空白だけの観測VINは、受け付ける段階でも無視されます。
    ///
    /// 責務: 正規化後に空になるVINで、状態が変わらないことを確認します。
    func testObservedVINRegistrationIgnoresBlankVIN() {
        let state = VehicleManagementState()
        for vin in ["", "   ", "\n\t "] {
            XCTAssertEqual(applied(.observedVINRegistrationRequested(vin), to: state), state, "\(vin.debugDescription)")
        }
    }

    /// 登録取消は、観測と編集中のプロフィールを消して操作待ちへ戻し、ほかの値は保ちます。
    ///
    /// 責務: 登録中の状態から取消した時に、観測・編集中が消え、一覧と接続対象が残ることを確認します。
    func testRegistrationCancelledClearsPendingAndEditingOnly() {
        var state = confirmingState(snapshot(vin: "V1"))
        state.phase = .registering
        state.editingVehicle = VehicleProfile(vin: "V1", name: "")
        let kept = VehicleProfile(vin: "KEPT", name: "kept")
        state.vehicles = [kept]
        state.connectionVehicle = kept

        let result = applied(.registrationCancelled, to: state)

        XCTAssertEqual(result.phase, .idle)
        XCTAssertNil(result.pendingIdentification)
        XCTAssertNil(result.editingVehicle)
        XCTAssertEqual(result.vehicles, [kept])
        XCTAssertEqual(result.connectionVehicle, kept)
    }

    /// 登録済みの車両IDで編集を始めると、その車両が編集対象になります。
    ///
    /// 責務: 複数台のうち指定IDの1台だけが編集対象になり、`.editing` へ進むことを確認します。
    func testEditRequestedSelectsMatchingVehicle() {
        let target = VehicleProfile(vin: "V1", name: "target")
        var state = VehicleManagementState()
        state.vehicles = [VehicleProfile(vin: "V0", name: "other"), target]
        let result = applied(.editRequested(target.id), to: state)
        XCTAssertEqual(result.editingVehicle, target)
        XCTAssertEqual(result.phase, .editing)
    }

    /// 存在しない車両IDや空の一覧では、編集を始めず状態を変えません。
    ///
    /// 責務: 一覧にないIDと空の一覧の両方で、状態が完全に同じままであることを確認します。
    func testEditRequestedWithUnknownIDOrEmptyListDoesNothing() {
        var populated = VehicleManagementState()
        populated.vehicles = [VehicleProfile(vin: "V1", name: "one")]
        XCTAssertEqual(applied(.editRequested(VehicleID()), to: populated), populated)
        let empty = VehicleManagementState()
        XCTAssertEqual(applied(.editRequested(VehicleID()), to: empty), empty)
    }

    /// 編集の取消は、編集対象を消して操作待ちへ戻します。
    ///
    /// 責務: 編集中の状態から取消した時に、編集対象が消え、一覧が残ることを確認します。
    func testEditCancelledClearsEditingAndReturnsToIdle() {
        let vehicle = VehicleProfile(vin: "V1", name: "one")
        var state = VehicleManagementState()
        state.vehicles = [vehicle]
        state.editingVehicle = vehicle
        state.phase = .editing

        let result = applied(.editCancelled, to: state)

        XCTAssertNil(result.editingVehicle)
        XCTAssertEqual(result.phase, .idle)
        XCTAssertEqual(result.vehicles, [vehicle])
    }

    /// 担当外の操作は、状態を変えません。
    ///
    /// 責務: 登録・編集と無関係な操作を適用しても、状態が完全に同じままであることを確認します。
    func testUnrelatedActionsDoNotChangeState() {
        let vehicle = VehicleProfile(vin: "V1", name: "one")
        var state = confirmingState(snapshot(vin: "V1"))
        state.vehicles = [vehicle]
        let unrelated: [VehicleManagementAction] = [
            .accountIdentifierChanged("x"), .identificationRetryRequested, .vehicleSaved(vehicle),
            .vehicleDeleted(vehicle.id), .refreshRequested, .pidSettingsClosed
        ]
        for action in unrelated {
            XCTAssertEqual(applied(action, to: state), state, "\(action)")
        }
    }
}

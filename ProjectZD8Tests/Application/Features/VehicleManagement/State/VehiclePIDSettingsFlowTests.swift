import Foundation
import XCTest
@testable import ProjectZD8

/// 車両別PID収集設定の読込・選択変更・終了の状態遷移を検証します。
@MainActor
final class VehiclePIDSettingsFlowTests: XCTestCase {
    /// PID設定を扱う車両のIDです。
    private let vehicleID = VehicleID()

    /// 標準PID(定義あり・型式なし)の要求です。
    private let standardRequest = OBDPIDRequest(service: 0x01, pid: 0x0C)

    /// 車種専用PID(定義あり・型式あり)の要求です。
    private let specialRequest = OBDPIDRequest(service: 0x21, pid: 0x02)

    /// 定義に無いPIDの要求です。
    private let undefinedRequest = OBDPIDRequest(service: 0x01, pid: 0x7F)

    /// 指定した型式を持つPID定義を生成します。
    ///
    /// 責務: 要求と型式だけを差し替えた、最小のPID定義を作ります。
    /// - Parameters:
    ///   - request: 定義のService/PID。
    ///   - modelCode: 車種専用PIDの型式。標準PIDは `nil`。
    /// - Returns: 生成した定義。
    private func definition(_ request: OBDPIDRequest, modelCode: String? = nil) -> OBDPIDDefinition {
        OBDPIDDefinition(
            service: request.service,
            pid: request.pid,
            vehicleModelCode: modelCode,
            nameKey: "test.pid.\(request.service).\(request.pid)",
            requiredByteCount: 1,
            formula: "A",
            unit: "unit",
            minimumValue: 0,
            maximumValue: 255,
            sourceURI: "test://pid",
            revision: 1
        )
    }

    /// 指定車両・要求・収集状態の対応PIDを生成します。
    ///
    /// 責務: 1件の対応PID設定を固定日時で作ります。
    /// - Parameters:
    ///   - request: 対応PIDのService/PID。
    ///   - enabled: 収集有効状態。
    ///   - vehicleID: 車両ID。省略時は検証対象の車両。
    /// - Returns: 生成した対応PID。
    private func capability(_ request: OBDPIDRequest, enabled: Bool, vehicleID: VehicleID? = nil) -> VehiclePIDCapability {
        VehiclePIDCapability(
            vehicleID: vehicleID ?? self.vehicleID,
            request: request,
            isCollectionEnabled: enabled,
            discoveredAt: Date(timeIntervalSince1970: 1)
        )
    }

    /// 標準PIDと車種専用PIDの定義を持つ定義 Repository を生成します。
    ///
    /// 責務: 標準1件と型式「ZD8」付き1件の定義を返す Repository を作ります。
    /// - Parameter failsRead: 読込を失敗させる場合は `true`。
    /// - Returns: 生成した定義 Repository。
    private func definitions(failsRead: Bool = false) -> StubOBDPIDDefinitionRepository {
        StubOBDPIDDefinitionRepository(
            definitions: [definition(standardRequest), definition(specialRequest, modelCode: "ZD8")],
            failsRead: failsRead
        )
    }

    /// 標準・専用・定義なしの3件を持つ車両の対応PID Repository を生成します。
    ///
    /// 責務: 検証対象の車両に3件(標準=有効、専用=無効、定義なし=有効)の対応PIDを持たせます。
    /// - Returns: 生成した対応PID Repository。
    private func capabilities() -> ScriptedVehiclePIDCapabilityRepository {
        ScriptedVehiclePIDCapabilityRepository(capabilitiesByVehicle: [
            vehicleID: [
                capability(standardRequest, enabled: true),
                capability(specialRequest, enabled: false),
                capability(undefinedRequest, enabled: true)
            ]
        ])
    }

    /// 操作を適用した結果の状態を返します。
    ///
    /// 責務: 与えた状態へ1件の操作を適用した後の状態を返します。
    /// - Parameters:
    ///   - flow: 適用する処理。
    ///   - action: 適用する操作。
    ///   - state: 適用前の状態。
    /// - Returns: 適用後の状態。
    private func applied(
        _ flow: VehiclePIDSettingsFlow,
        _ action: VehicleManagementAction,
        to state: VehicleManagementState
    ) -> VehicleManagementState {
        var result = state
        flow.apply(action, to: &result)
        return result
    }

    /// 設定を表示している状態を生成します。
    ///
    /// 責務: 検証対象の車両のPID設定を表示している状態(3件の選択項目)を作ります。
    /// - Returns: 生成した状態。
    private func displayingState() -> VehicleManagementState {
        var state = VehicleManagementState()
        state.pidSettingsVehicleID = vehicleID
        state.pidSelectionItems = [
            VehiclePIDSelectionItem(id: standardRequest, nameKey: "a", isEnabled: true, vehicleModelCode: nil),
            VehiclePIDSelectionItem(id: specialRequest, nameKey: "b", isEnabled: false, vehicleModelCode: "ZD8")
        ]
        return state
    }

    /// 設定の表示を求めると、名称・収集状態・型式つきの選択一覧になり、失敗文言が消えます。
    ///
    /// 責務: 定義のあるPIDは名称と型式を持ち、定義にないPIDは名称・型式なしで一覧へ入ることを確認します。
    func testRequestedLoadsItemsWithNamesAndModelCodes() {
        var state = VehicleManagementState()
        state.failureKey = "garage.pid_settings.error"
        let flow = VehiclePIDSettingsFlow(pidCapabilityRepository: capabilities(), pidDefinitionRepository: definitions())

        let result = applied(flow, .pidSettingsRequested(vehicleID), to: state)

        XCTAssertEqual(result.pidSettingsVehicleID, vehicleID)
        XCTAssertNil(result.failureKey)
        XCTAssertEqual(result.pidSelectionItems, [
            VehiclePIDSelectionItem(id: standardRequest, nameKey: "test.pid.1.12", isEnabled: true, vehicleModelCode: nil),
            VehiclePIDSelectionItem(id: specialRequest, nameKey: "test.pid.33.2", isEnabled: false, vehicleModelCode: "ZD8"),
            VehiclePIDSelectionItem(id: undefinedRequest, nameKey: nil, isEnabled: true, vehicleModelCode: nil)
        ])
    }

    /// 対応PIDが1件もない車両でも、空の一覧で設定を表示します。
    ///
    /// 責務: 空の対応PIDが失敗扱いにならず、対象車両IDと空の一覧になることを確認します。
    func testRequestedWithNoCapabilitiesShowsEmptyList() {
        let flow = VehiclePIDSettingsFlow(
            pidCapabilityRepository: ScriptedVehiclePIDCapabilityRepository(),
            pidDefinitionRepository: definitions()
        )
        let result = applied(flow, .pidSettingsRequested(vehicleID), to: VehicleManagementState())
        XCTAssertEqual(result.pidSettingsVehicleID, vehicleID)
        XCTAssertEqual(result.pidSelectionItems, [])
        XCTAssertNil(result.failureKey)
    }

    /// 対応PIDの保存先か定義の参照先が無いときは、失敗文言だけを設定します。
    ///
    /// 責務: どちらかの境界が `nil` のとき、失敗文言以外の状態が変わらないことを確認します。
    func testRequestedWithoutRepositoriesReportsFailureOnly() {
        let flows = [
            VehiclePIDSettingsFlow(pidCapabilityRepository: nil, pidDefinitionRepository: definitions()),
            VehiclePIDSettingsFlow(pidCapabilityRepository: capabilities(), pidDefinitionRepository: nil),
            VehiclePIDSettingsFlow(pidCapabilityRepository: nil, pidDefinitionRepository: nil)
        ]
        let state = displayingState()
        for flow in flows {
            var expected = state
            expected.failureKey = "garage.pid_settings.error"
            XCTAssertEqual(applied(flow, .pidSettingsRequested(vehicleID), to: state), expected)
        }
    }

    /// 定義の読込か対応PIDの読込が失敗したときは、失敗文言だけを設定し、表示中の内容を保ちます。
    ///
    /// 責務: 読込失敗で表示中の車両・一覧を壊さず、失敗文言だけが加わることを確認します。
    func testRequestedWhenReadFailsReportsFailureAndKeepsDisplay() {
        let failingCapabilities = capabilities()
        failingCapabilities.failingReadVehicleIDs = [vehicleID]
        let flows = [
            VehiclePIDSettingsFlow(pidCapabilityRepository: capabilities(), pidDefinitionRepository: definitions(failsRead: true)),
            VehiclePIDSettingsFlow(pidCapabilityRepository: failingCapabilities, pidDefinitionRepository: definitions())
        ]
        let state = displayingState()
        for flow in flows {
            var expected = state
            expected.failureKey = "garage.pid_settings.error"
            XCTAssertEqual(applied(flow, .pidSettingsRequested(vehicleID), to: state), expected)
        }
    }

    /// 表示中の車両で選択を変えると、保存し、該当項目だけを更新します。
    ///
    /// 責務: 有効化と無効化の両方で、保存内容(状態・要求・車両)と一覧の該当項目だけの更新を確認します。
    func testCollectionChangedPersistsAndUpdatesOnlyMatchingItem() {
        let repository = capabilities()
        let flow = VehiclePIDSettingsFlow(pidCapabilityRepository: repository, pidDefinitionRepository: definitions())
        var state = displayingState()

        state = applied(flow, .pidCollectionChanged(specialRequest, true), to: state)
        state = applied(flow, .pidCollectionChanged(standardRequest, false), to: state)

        XCTAssertEqual(state.pidSelectionItems.map(\.isEnabled), [false, true])
        XCTAssertEqual(repository.changes, [
            .init(isEnabled: true, request: specialRequest, vehicleID: vehicleID),
            .init(isEnabled: false, request: standardRequest, vehicleID: vehicleID)
        ])
    }

    /// 一覧にない要求でも保存し、一覧と状態は変えません。
    ///
    /// 責務: 表示一覧に存在しない要求の変更が、保存だけ行われ一覧を変えないことを確認します。
    func testCollectionChangedForUnlistedRequestPersistsWithoutChangingItems() {
        let repository = capabilities()
        let flow = VehiclePIDSettingsFlow(pidCapabilityRepository: repository, pidDefinitionRepository: definitions())
        let state = displayingState()

        let result = applied(flow, .pidCollectionChanged(undefinedRequest, false), to: state)

        XCTAssertEqual(result, state)
        XCTAssertEqual(repository.changes, [.init(isEnabled: false, request: undefinedRequest, vehicleID: vehicleID)])
    }

    /// 表示中の車両がないとき、または保存先が無いときは、何も保存せず状態も変えません。
    ///
    /// 責務: 設定を開いていない場合と保存先が `nil` の場合の両方で、状態が変わらず保存もされないことを確認します。
    func testCollectionChangedWithoutDisplayedVehicleOrRepositoryDoesNothing() {
        let repository = capabilities()
        let noVehicleFlow = VehiclePIDSettingsFlow(pidCapabilityRepository: repository, pidDefinitionRepository: definitions())
        let noRepositoryFlow = VehiclePIDSettingsFlow(pidCapabilityRepository: nil, pidDefinitionRepository: definitions())
        var hidden = displayingState()
        hidden.pidSettingsVehicleID = nil

        XCTAssertEqual(applied(noVehicleFlow, .pidCollectionChanged(standardRequest, false), to: hidden), hidden)
        let shown = displayingState()
        XCTAssertEqual(applied(noRepositoryFlow, .pidCollectionChanged(standardRequest, false), to: shown), shown)
        XCTAssertEqual(repository.changes, [])
    }

    /// 保存に失敗したときは、一覧を変えず失敗文言だけを設定します。
    ///
    /// 責務: 保存失敗で表示上の収集状態が書き換わらないことを確認します。
    func testCollectionChangedWhenSaveFailsKeepsItemsAndReportsFailure() {
        let repository = capabilities()
        repository.failsSave = true
        let flow = VehiclePIDSettingsFlow(pidCapabilityRepository: repository, pidDefinitionRepository: definitions())
        let state = displayingState()
        var expected = state
        expected.failureKey = "garage.pid_settings.error"

        XCTAssertEqual(applied(flow, .pidCollectionChanged(standardRequest, false), to: state), expected)
        XCTAssertEqual(repository.changes, [])
    }

    /// 設定を閉じると、対象車両と選択一覧を消し、ほかの値は保ちます。
    ///
    /// 責務: 閉じる操作が車両IDと一覧だけを消し、失敗文言などを残すことを確認します。
    func testClosedClearsVehicleAndItemsOnly() {
        var state = displayingState()
        state.failureKey = "garage.error.sync"
        let flow = VehiclePIDSettingsFlow(pidCapabilityRepository: nil, pidDefinitionRepository: nil)

        let result = applied(flow, .pidSettingsClosed, to: state)

        XCTAssertNil(result.pidSettingsVehicleID)
        XCTAssertEqual(result.pidSelectionItems, [])
        XCTAssertEqual(result.failureKey, "garage.error.sync")
    }

    /// 担当外の操作は、状態を変えません。
    ///
    /// 責務: PID設定と無関係な操作を適用しても、状態が完全に同じままであることを確認します。
    func testUnrelatedActionsDoNotChangeState() {
        let flow = VehiclePIDSettingsFlow(pidCapabilityRepository: capabilities(), pidDefinitionRepository: definitions())
        let state = displayingState()
        let unrelated: [VehicleManagementAction] = [
            .accountIdentifierChanged("x"), .identificationConfirmed, .registrationCancelled, .editCancelled,
            .refreshRequested, .editRequested(vehicleID)
        ]
        for action in unrelated {
            XCTAssertEqual(applied(flow, action, to: state), state, "\(action)")
        }
    }
}

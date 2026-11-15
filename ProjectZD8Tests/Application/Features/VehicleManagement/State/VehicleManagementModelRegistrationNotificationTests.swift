import Foundation
import XCTest
@testable import ProjectZD8

/// `VehicleManagementModel` の注入点 `vehicleDidRegister` が、新規登録の完了時だけ登録車両で1回呼ばれ、
/// 紐付けの失敗が登録を取り消さずに状態へ現れることを検証します。
@MainActor
final class VehicleManagementModelRegistrationNotificationTests: XCTestCase {
    /// サインイン中のアカウントです。
    private static let account = "account-unit6"

    /// 観測VINです。
    private static let vin = "JF1ZD8A11P9000001"

    /// 接続の識別で読み取るVIN(未登録)です。
    private static let identifiedVIN = "JF1ZD8A11P9000002"

    /// 車両の保存先 fake です。
    private let repository = AccountScopedVehicleRepositoryFake()

    /// 紐付けに渡された車両とアカウントです。
    private var registrations: [(vehicle: VehicleProfile, account: String)] = []

    /// 紐付けで投げるエラーです。`nil` なら成功します。
    private var assignmentFailure: (any Error)?

    /// サインインして車両一覧の読込を終えたモデルを作ります。
    ///
    /// 責務: 紐付けの呼び出しを記録するモデルを組み立て、読込完了まで上限付きで待ちます。
    /// - Returns: 一覧表示中のモデル。
    private func signedInModel(file: StaticString = #filePath, line: UInt = #line) async throws -> VehicleManagementModel {
        let model = VehicleManagementModel(
            state: VehicleManagementState(),
            repository: repository,
            identifyForConnection: IdentifyVehicleForConnectionUseCase(identification: ScriptedVehicleIdentificationPort(
                result: .success(VehicleIdentificationSnapshot(vin: Self.identifiedVIN, fields: [], observedAt: Date(timeIntervalSince1970: 0)))
            )),
            photoImporter: ObservedVINRegistrationPhotoImportStub(),
            vehicleDidRegister: { [weak self] vehicle, account in
                self?.registrations.append((vehicle, account))
                if let failure = self?.assignmentFailure { throw failure }
            }
        )
        model.send(.accountIdentifierChanged(Self.account))
        try await BLEBoundedWaiter.waitUntil("車両一覧の読込", file: file, line: line) { model.state.hasLoadedVehicles }
        return model
    }

    /// 観測VINから新規登録を始めて保存し、保存の決着(一覧表示か失敗)まで待ちます。
    ///
    /// 責務: 登録画面の入力と保存を送り、編集中の車両を返します。
    /// - Parameter model: 一覧表示中のモデル。
    /// - Returns: 保存を送った車両。
    private func registerFromObservedVIN(_ model: VehicleManagementModel, file: StaticString = #filePath, line: UInt = #line) async throws -> VehicleProfile {
        model.send(.observedVINRegistrationRequested(Self.vin))
        var vehicle = try XCTUnwrap(model.state.editingVehicle, file: file, line: line)
        vehicle.name = "BRZ"
        model.send(.vehicleSaved(vehicle))
        try await BLEBoundedWaiter.waitUntil("保存の決着", file: file, line: line) {
            model.state.phase == .idle || model.state.phase == .failed
        }
        return vehicle
    }

    /// 新規登録の完了時に、登録した車両とアカウントで1回呼ばれ、失敗表示は出ません。
    ///
    /// 責務: 呼び出し回数・渡された車両のIDとVIN・アカウント・失敗キーを確認します。
    func testNewRegistrationNotifiesOnceWithRegisteredVehicle() async throws {
        let model = try await signedInModel()

        let vehicle = try await registerFromObservedVIN(model)

        XCTAssertEqual(registrations.count, 1)
        XCTAssertEqual(registrations.first?.vehicle.id, vehicle.id)
        XCTAssertEqual(registrations.first?.vehicle.vin, Self.vin)
        XCTAssertEqual(registrations.first?.account, Self.account)
        XCTAssertNil(model.state.failureKey)
        XCTAssertEqual(model.state.phase, .idle)
    }

    /// 接続の識別から登録確認を経た新規登録でも1回呼ばれます。
    ///
    /// 責務: 識別 → 登録確認 → 登録 → 保存の経路で、登録車両を引数に1回呼ばれることを確認します。
    func testRegistrationAfterIdentificationNotifiesOnce() async throws {
        let model = try await signedInModel()
        let endpoint = OBDConnectionEndpoint(transport: .bluetoothLowEnergy, systemIdentifier: "id", displayName: "A")
        model.send(.identifyRequested(endpoint))
        try await BLEBoundedWaiter.waitUntil("登録確認") { model.state.phase == .confirmingIdentification }
        model.send(.identificationConfirmed)
        let vehicle = try XCTUnwrap(model.state.editingVehicle)

        model.send(.vehicleSaved(vehicle))
        try await BLEBoundedWaiter.waitUntil("保存の完了") { model.state.phase == .idle }

        XCTAssertEqual(registrations.map(\.vehicle.id), [vehicle.id])
        XCTAssertEqual(registrations.first?.vehicle.vin, Self.identifiedVIN)
    }

    /// 登録の保存に失敗した時は呼ばれません。
    ///
    /// 責務: 保存失敗で失敗表示になり、紐付けが呼ばれないことを確認します。
    func testFailedRegistrationDoesNotNotify() async throws {
        let model = try await signedInModel()
        repository.saveFailure = VehicleRecordingTestError.vehicleSaveFailed

        _ = try await registerFromObservedVIN(model)

        XCTAssertEqual(model.state.phase, .failed)
        XCTAssertTrue(registrations.isEmpty)
    }

    /// 既存車両の編集保存では呼ばれません。
    ///
    /// 責務: 登録済み車両の編集を保存しても紐付けが呼ばれないことを確認します。
    func testEditingExistingVehicleDoesNotNotify() async throws {
        let existing = VehicleProfile(vin: Self.vin, name: "BRZ")
        repository.vehiclesByAccount[Self.account] = [existing]
        let model = try await signedInModel()
        model.send(.editRequested(existing.id))
        XCTAssertEqual(model.state.phase, .editing)
        var edited = try XCTUnwrap(model.state.editingVehicle)
        edited.name = "BRZ renamed"

        model.send(.vehicleSaved(edited))
        try await BLEBoundedWaiter.waitUntil("編集の保存") { model.state.vehicles.first?.name == "BRZ renamed" }
        try await BLEBoundedWaiter.settle()

        XCTAssertTrue(registrations.isEmpty)
    }

    /// 紐付けが失敗しても車両の登録は保存されたままで、失敗が状態に現れます。
    ///
    /// 責務: 保存先と一覧に車両が残り、失敗キーが `garage.error.session_assignment` になることを確認します。
    func testAssignmentFailureKeepsRegistrationAndShowsFailure() async throws {
        let model = try await signedInModel()
        assignmentFailure = VehicleRecordingTestError.sessionAssignmentFailed

        let vehicle = try await registerFromObservedVIN(model)

        XCTAssertEqual(registrations.count, 1)
        XCTAssertEqual(repository.vehiclesByAccount[Self.account]?.map(\.id), [vehicle.id])
        XCTAssertTrue(model.state.vehicles.contains { $0.id == vehicle.id })
        XCTAssertEqual(model.state.failureKey, "garage.error.session_assignment")
        XCTAssertNil(model.state.editingVehicle)
    }
}

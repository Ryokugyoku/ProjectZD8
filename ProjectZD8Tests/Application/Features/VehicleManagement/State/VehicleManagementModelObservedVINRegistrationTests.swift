import Foundation
import XCTest
@testable import ProjectZD8

/// `VehicleManagementAction.observedVINRegistrationRequested` を受けた `VehicleManagementModel` が、
/// 観測VINを入力済みにした車両登録の状態へ進むことを検証します。
@MainActor
final class VehicleManagementModelObservedVINRegistrationTests: XCTestCase {
    /// 未登録ログで観測したVINです。
    private let vin = "JF1ZD8A11P9000001"
    /// 車両保存の fake です。
    private var repository: ObservedVINRegistrationVehicleRepositoryFake!

    /// 指定段階から始まるモデルを作ります。
    ///
    /// 責務: 空の車両一覧を返す fake とデモ識別を注入したモデルを組み立てます。
    /// - Parameter phase: 初期段階。
    /// - Returns: テスト対象のモデル。
    private func makeModel(phase: VehicleManagementState.Phase = .idle) -> VehicleManagementModel {
        repository = ObservedVINRegistrationVehicleRepositoryFake()
        var state = VehicleManagementState()
        state.phase = phase
        return VehicleManagementModel(
            state: state,
            repository: repository,
            identifyForConnection: IdentifyVehicleForConnectionUseCase(identification: DemoVehicleIdentificationAdapter()),
            photoImporter: ObservedVINRegistrationPhotoImportStub()
        )
    }

    /// 一覧表示中に要求すると、VINを入力済みにした新規登録へ進みます。
    ///
    /// 責務: 段階が `.registering` になり、編集中の新規プロフィールが観測VINを持つことを確認します。
    func testRequestFromIdleBeginsRegistrationWithVIN() throws {
        let model = makeModel(phase: .idle)
        model.send(.observedVINRegistrationRequested(vin))
        XCTAssertEqual(model.state.phase, .registering)
        let editing = try XCTUnwrap(model.state.editingVehicle)
        XCTAssertEqual(editing.vin, vin)
        XCTAssertNil(model.state.pendingIdentification)
    }

    /// 失敗表示中に要求しても、VINを入力済みにした新規登録へ進みます。
    ///
    /// 責務: `.failed` から `.registering` へ進み、観測VINが渡ることを確認します。
    func testRequestFromFailedBeginsRegistrationWithVIN() {
        let model = makeModel(phase: .failed)
        model.send(.observedVINRegistrationRequested(vin))
        XCTAssertEqual(model.state.phase, .registering)
        XCTAssertEqual(model.state.editingVehicle?.vin, vin)
    }

    /// 開始した登録はそのまま保存でき、保存された車両は観測VINを持ちます。
    ///
    /// 責務: 既存の保存操作 `.vehicleSaved` で Repository へ届いた車両のVINが観測VINであることを確認します。
    func testRegistrationStartedFromVINSavesVehicleWithVIN() async throws {
        let model = makeModel(phase: .idle)
        model.send(.accountIdentifierChanged("account-unit5"))
        try await BLEBoundedWaiter.waitUntil("車両一覧の読込") { model.state.hasLoadedVehicles }
        model.send(.observedVINRegistrationRequested(vin))
        var draft = try XCTUnwrap(model.state.editingVehicle)
        draft.name = "BRZ"

        model.send(.vehicleSaved(draft))
        try await BLEBoundedWaiter.waitUntil("車両の保存") { !self.repository.savedVehicles.isEmpty }

        XCTAssertEqual(repository.savedVehicles.map(\.vin), [vin])
    }

    /// 開始した登録はキャンセルで一覧へ戻せます。
    ///
    /// 責務: 既存の `.registrationCancelled` で `.idle` に戻り、編集中のプロフィールが消えることを確認します。
    func testRegistrationStartedFromVINCanBeCancelled() {
        let model = makeModel(phase: .idle)
        model.send(.observedVINRegistrationRequested(vin))
        model.send(.registrationCancelled)
        XCTAssertEqual(model.state.phase, .idle)
        XCTAssertNil(model.state.editingVehicle)
    }
}

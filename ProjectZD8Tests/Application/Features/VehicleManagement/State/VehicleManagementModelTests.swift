import Foundation
import XCTest
@testable import ProjectZD8

/// 車両管理モデルが識別失敗を原因別の表示状態へ変換することを検証します。
@MainActor
final class VehicleManagementModelTests: XCTestCase {
    /// 全識別段階が実機報告用の安定診断コードを持つことを検証します。
    ///
    /// 責務: 車両識別段階と画面表示用診断コードの対応を固定します。
    func testIdentificationStagesExposeStableDiagnosticCodes() {
        XCTAssertEqual(VehicleIdentificationError.Stage.endpointValidation.diagnosticCode, "ENDPOINT")
        XCTAssertEqual(VehicleIdentificationError.Stage.transportCreation.diagnosticCode, "TRANSPORT-CREATE")
        XCTAssertEqual(VehicleIdentificationError.Stage.transportOpen.diagnosticCode, "TRANSPORT-OPEN")
        XCTAssertEqual(VehicleIdentificationError.Stage.adapterReset.diagnosticCode, "ATZ")
        XCTAssertEqual(VehicleIdentificationError.Stage.adapterConfiguration.diagnosticCode, "AT-CONFIG")
        XCTAssertEqual(VehicleIdentificationError.Stage.adapterIdentity.diagnosticCode, "ATI")
        XCTAssertEqual(VehicleIdentificationError.Stage.vehicleIdentificationRequest.diagnosticCode, "0902-REQUEST")
        XCTAssertEqual(VehicleIdentificationError.Stage.vehicleIdentificationParsing.diagnosticCode, "0902-PARSE")
        XCTAssertEqual(VehicleIdentificationError.Stage.protocolDescription.diagnosticCode, "ATDP")
    }

    /// デモ車両も通常登録操作を経てRepositoryへ保存します。
    ///
    /// 責務: デモ識別結果が保存省略されず通常の車両プロフィールとして登録されることを確認します。
    func testDemoVehicleUsesNormalRegistrationPersistence() async throws {
        let repository = VehicleRepositoryFake()
        let model = VehicleManagementModel(
            state: VehicleManagementState(),
            repository: repository,
            identifyForConnection: IdentifyVehicleForConnectionUseCase(
                identification: DemoVehicleIdentificationAdapter()
            ),
            photoImporter: VehiclePhotoImportPortFake()
        )
        model.send(.accountIdentifierChanged("test-account"))
        try await waitUntil { model.state.hasLoadedVehicles }

        model.send(.identifyRequested(OBDConnectionEndpoint(adapter: DemoOBDAdapter.candidate)))
        try await waitUntil { model.state.phase == .confirmingIdentification }
        model.send(.identificationConfirmed)
        let draft = try XCTUnwrap(model.state.editingVehicle)
        model.send(.vehicleSaved(draft))
        try await waitUntil { model.state.phase == .idle && model.state.vehicles.count == 1 }

        let expectedVIN = DemoOBDAdapter.syntheticVIN(for: OBDConnectionEndpoint(adapter: DemoOBDAdapter.candidate))
        XCTAssertEqual(repository.savedVehicles.map(\.vin), [expectedVIN])
        XCTAssertEqual(model.state.vehicles.map(\.vin), [expectedVIN])
    }

    /// 未登録車両は登録保存が成功した後にだけ接続開始へ引き渡します。
    ///
    /// 責務: 車両登録の保存完了前後で接続確定通知の発行時点が変わることを確認します。
    func testUnregisteredVehicleResolvesConnectionAfterRegistrationSave() async throws {
        let repository = VehicleRepositoryFake()
        var resolvedVehicles: [VehicleProfile] = []
        let model = VehicleManagementModel(
            state: VehicleManagementState(),
            repository: repository,
            identifyForConnection: IdentifyVehicleForConnectionUseCase(
                identification: DemoVehicleIdentificationAdapter()
            ),
            photoImporter: VehiclePhotoImportPortFake(),
            connectionVehicleDidResolve: { vehicle, _, _ in resolvedVehicles.append(vehicle) }
        )
        model.send(.accountIdentifierChanged("test-account"))
        try await waitUntil { model.state.hasLoadedVehicles }

        model.send(.identifyRequested(OBDConnectionEndpoint(adapter: DemoOBDAdapter.candidate)))
        try await waitUntil { model.state.phase == .confirmingIdentification }
        XCTAssertTrue(resolvedVehicles.isEmpty)

        model.send(.identificationConfirmed)
        let draft = try XCTUnwrap(model.state.editingVehicle)
        model.send(.vehicleSaved(draft))
        try await waitUntil { model.state.phase == .idle && resolvedVehicles.count == 1 }

        XCTAssertEqual(resolvedVehicles.map(\.id), [draft.id])
    }

    /// 未登録車両の登録をキャンセルした場合は接続開始へ引き渡しません。
    ///
    /// 責務: 登録キャンセル後に接続確定通知が発行されないことを確認します。
    func testRegistrationCancellationDoesNotResolveConnection() async throws {
        var resolutionCount = 0
        let model = VehicleManagementModel(
            state: VehicleManagementState(),
            repository: VehicleRepositoryFake(),
            identifyForConnection: IdentifyVehicleForConnectionUseCase(
                identification: DemoVehicleIdentificationAdapter()
            ),
            photoImporter: VehiclePhotoImportPortFake(),
            connectionVehicleDidResolve: { _, _, _ in resolutionCount += 1 }
        )
        model.send(.accountIdentifierChanged("test-account"))
        try await waitUntil { model.state.hasLoadedVehicles }

        model.send(.identifyRequested(OBDConnectionEndpoint(adapter: DemoOBDAdapter.candidate)))
        try await waitUntil { model.state.phase == .confirmingIdentification }
        model.send(.identificationConfirmed)
        XCTAssertEqual(model.state.phase, .registering)
        model.send(.registrationCancelled)

        XCTAssertEqual(model.state.phase, .idle)
        XCTAssertNil(model.state.pendingIdentification)
        XCTAssertNil(model.state.editingVehicle)
        XCTAssertEqual(resolutionCount, 0)
    }

    /// 登録確認中の再読込要求が確認対象の識別観測を破棄しないことを検証します。
    ///
    /// 責務: 進行中の新規車両登録確認がGarage表示時の一覧再読込によって中断されないことを確認します。
    func testRefreshRequestedDuringRegistrationConfirmationPreservesPendingIdentification() async throws {
        let model = VehicleManagementModel(
            state: VehicleManagementState(),
            repository: VehicleRepositoryFake(),
            identifyForConnection: IdentifyVehicleForConnectionUseCase(
                identification: DemoVehicleIdentificationAdapter()
            ),
            photoImporter: VehiclePhotoImportPortFake()
        )
        model.send(.accountIdentifierChanged("test-account"))
        try await waitUntil { model.state.hasLoadedVehicles }

        model.send(.identifyRequested(OBDConnectionEndpoint(adapter: DemoOBDAdapter.candidate)))
        try await waitUntil { model.state.phase == .confirmingIdentification }
        let pendingIdentification = try XCTUnwrap(model.state.pendingIdentification)

        model.send(.refreshRequested)
        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(model.state.phase, .confirmingIdentification)
        XCTAssertEqual(model.state.pendingIdentification, pendingIdentification)
    }

    /// 識別境界の型付きエラーを診断可能な表示キーへ分離します。
    ///
    /// 責務: 実車識別の主要失敗段階が同じ汎用文言へ潰れないことを確認します。
    func testIdentificationErrorsUseStageSpecificFailureKeys() async throws {
        let expectations: [(VehicleIdentificationError, String)] = [
            (.pidCatalogUnavailable, "garage.error.pid_catalog"),
            (.connectionFailed, "garage.error.connection"),
            (.responseTimedOut, "garage.error.timeout"),
            (.commandRejected, "garage.error.command_rejected"),
            (.malformedResponse, "garage.error.malformed_response")
        ]

        for (error, expectedKey) in expectations {
            let model = makeModel(error: error)
            model.send(.accountIdentifierChanged("test-account"))
            try await waitUntil { model.state.hasLoadedVehicles }

            model.send(.identifyRequested(endpoint))
            try await waitUntil { model.state.phase == .failed }

            XCTAssertEqual(model.state.failureKey, expectedKey)
        }
    }

    /// 通信境界が返した失敗段階と原因を別々の表示状態として保持します。
    ///
    /// 責務: `0902` 要求の期限切れが段階コードと期限切れ文言を失わず状態へ反映されることを確認します。
    func testStagedIdentificationErrorPreservesStageAndCause() async throws {
        let model = makeModel(error: .stageFailed(.vehicleIdentificationRequest, .responseTimedOut))
        model.send(.accountIdentifierChanged("test-account"))
        try await waitUntil { model.state.hasLoadedVehicles }

        model.send(.identifyRequested(endpoint))
        try await waitUntil { model.state.phase == .failed }

        XCTAssertEqual(model.state.identificationFailureStage, .vehicleIdentificationRequest)
        XCTAssertEqual(model.state.failureKey, "garage.error.timeout")
    }

    /// 指定識別エラーを返す車両管理モデルを生成します。
    ///
    /// 責務: 1件の識別失敗を観測できるテスト用依存関係を組み立てます。
    /// - Parameter error: 識別境界から返す型付きエラー。
    /// - Returns: 空の車両一覧を読み込み済みにできる車両管理モデル。
    private func makeModel(error: VehicleIdentificationError) -> VehicleManagementModel {
        VehicleManagementModel(
            state: VehicleManagementState(),
            repository: VehicleRepositoryFake(),
            identifyForConnection: IdentifyVehicleForConnectionUseCase(
                identification: FailingVehicleIdentificationPort(error: error)
            ),
            photoImporter: VehiclePhotoImportPortFake()
        )
    }

    /// テスト用のEXシリアル終端です。
    private var endpoint: OBDConnectionEndpoint {
        .init(transport: .serial, systemIdentifier: "/dev/cu.test", displayName: "OBDLink EX")
    }

    /// 指定条件が成立するまでMainActor上の非同期処理へ実行機会を渡します。
    ///
    /// 責務: 1件のモデル状態条件を上限回数内で待機します。
    /// - Parameter condition: 成立を待つ状態条件。
    /// - Throws: 上限回数までに条件が成立しない場合のテスト失敗。
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !condition() { await Task.yield() }
        guard condition() else { throw VehicleManagementModelTestError.conditionTimedOut }
    }
}

/// 車両管理モデルテストの待機失敗です。
private enum VehicleManagementModelTestError: Error {
    /// 期待状態が上限回数までに成立しませんでした。
    case conditionTimedOut
}

/// 車両管理テストへ空の保存状態を提供します。
@MainActor
private final class VehicleRepositoryFake: VehicleRepository {
    /// 保存要求として受け取った車両です。
    private(set) var savedVehicles: [VehicleProfile] = []

    /// 空の登録車両一覧を返します。
    ///
    /// 責務: 指定アカウントのテスト用車両一覧を空として返します。
    /// - Parameter accountIdentifier: テスト用アカウント識別子。
    /// - Returns: 空の車両一覧。
    func loadVehicles(for accountIdentifier: String) async throws -> [VehicleProfile] { [] }

    /// テストでは車両を保存しません。
    ///
    /// 責務: 車両保存要求を副作用なしで受理します。
    /// - Parameters:
    ///   - vehicle: 保存対象として受け取る車両。
    ///   - accountIdentifier: テスト用アカウント識別子。
    func saveVehicle(_ vehicle: VehicleProfile, for accountIdentifier: String) async throws {
        savedVehicles.append(vehicle)
    }

    /// テストでは車両を削除しません。
    ///
    /// 責務: 車両削除要求を副作用なしで受理します。
    /// - Parameters:
    ///   - id: 削除対象として受け取る車両ID。
    ///   - accountIdentifier: テスト用アカウント識別子。
    func deleteVehicle(id: VehicleID, for accountIdentifier: String) async throws {}
}

/// 注入された識別エラーだけを返す境界です。
private struct FailingVehicleIdentificationPort: VehicleIdentificationPort {
    /// すべての識別要求で返すエラーです。
    let error: VehicleIdentificationError

    /// 指定された型付きエラーで識別を失敗させます。
    ///
    /// 責務: 1件の車両識別要求へ注入済みエラーを返します。
    /// - Parameter endpoint: テストでは参照しない接続終端。
    /// - Throws: 初期化時に注入された識別エラー。
    func identifyVehicle(using endpoint: OBDConnectionEndpoint) async throws -> VehicleIdentificationSnapshot {
        throw error
    }
}

/// 車両管理テストで画像取込を使用不能に保つ境界です。
private struct VehiclePhotoImportPortFake: VehiclePhotoImportPort {
    /// 空の画像データを返します。
    ///
    /// 責務: 画像取込要求を外部ファイルへアクセスせず完了します。
    /// - Parameter url: テストでは参照しない画像URL。
    /// - Returns: 空の画像データ。
    func importPhoto(at url: URL) async throws -> Data { Data() }
}

import Foundation
import XCTest
@testable import ProjectZD8

/// `VehicleManagementModel` の注入点 `connectionIdentificationWillBegin` / `connectionIdentificationDidEnd` が、
/// 手動接続の車両識別の直前と終了時(全結果)に1回ずつ呼ばれることを検証します。
@MainActor
final class VehicleManagementModelConnectionIdentificationNotificationTests: XCTestCase {
    /// サインイン中のアカウントです。
    private static let account = VehicleRecordingCoordinatorHarness.account

    /// 登録済み車両のVINです。
    private static let vin = "JF1ZD8A11P9000001"

    /// 手動接続の終端です。
    private static let endpoint = VehicleRecordingCoordinatorHarness.endpoint

    /// 呼び出しの発生順です。
    private var events: [String] = []

    /// 車両の保存先 fake です。
    private let repository = AccountScopedVehicleRepositoryFake()

    /// テスト中に作った識別の gate です。途中で失敗しても待ちが残らないよう、終了時に解放します。
    private var gates: [AdapterLinkSupervisionScriptedResponses<Bool>] = []

    /// 責務: 未解決の識別の待ちを失敗として解放します。
    override func tearDown() async throws {
        gates.forEach { $0.failAllPending() }
        gates.removeAll()
        try await super.tearDown()
    }

    /// 識別観測を作ります。
    ///
    /// 責務: 指定VINの観測を返します。
    /// - Parameter vin: 観測したVIN。
    /// - Returns: 識別観測。
    private static func snapshot(vin: String) -> VehicleIdentificationSnapshot {
        VehicleIdentificationSnapshot(vin: vin, fields: [], observedAt: Date(timeIntervalSince1970: 0))
    }

    /// 識別の開始・終了と車両確定の呼び出しを記録するモデルを作り、サインインして一覧の読込まで待ちます。
    ///
    /// 責務: 識別ポートと3つの注入点を記録先へ結び付けます。
    /// - Parameter port: 車両識別ポートの fake。
    /// - Returns: 一覧表示中のモデル。
    private func signedInModel(port: ScriptedVehicleIdentificationPort) async throws -> VehicleManagementModel {
        port.identificationDidStart = { [weak self] in self?.events.append("identify") }
        let model = VehicleManagementModel(
            state: VehicleManagementState(),
            repository: repository,
            identifyForConnection: IdentifyVehicleForConnectionUseCase(identification: port),
            photoImporter: ObservedVINRegistrationPhotoImportStub(),
            connectionVehicleDidResolve: { [weak self] _, _, _ in self?.events.append("resolved") },
            connectionIdentificationWillBegin: { [weak self] in self?.events.append("willBegin") },
            connectionIdentificationDidEnd: { [weak self] in self?.events.append("didEnd") }
        )
        model.send(.accountIdentifierChanged(Self.account))
        try await BLEBoundedWaiter.waitUntil("車両一覧の読込") { model.state.hasLoadedVehicles }
        return model
    }

    /// 識別を要求し、識別が終わるまで上限付きで待ちます。
    ///
    /// 責務: 識別要求を送り、終了の通知が届くまで待ちます。
    /// - Parameter model: 一覧表示中のモデル。
    private func identify(_ model: VehicleManagementModel, file: StaticString = #filePath, line: UInt = #line) async throws {
        model.send(.identifyRequested(Self.endpoint))
        try await BLEBoundedWaiter.waitUntil("識別の終了", file: file, line: line) { events.contains("didEnd") }
    }

    /// 登録済み車両が確定した場合、開始は識別の前、終了は車両確定の後に1回ずつ呼ばれます。
    ///
    /// 責務: 呼び出し順が「開始 → 識別 → 車両確定 → 終了」であることを確認します。
    func testRegisteredVehicleNotifiesBeginBeforeIdentificationAndEndAfterResolution() async throws {
        repository.vehiclesByAccount[Self.account] = [VehicleProfile(vin: Self.vin, name: "BRZ")]
        let model = try await signedInModel(port: ScriptedVehicleIdentificationPort(result: .success(Self.snapshot(vin: Self.vin))))

        try await identify(model)

        XCTAssertEqual(events, ["willBegin", "identify", "resolved", "didEnd"])
    }

    /// 未登録で登録確認へ進んだ場合も、開始と終了が1回ずつ呼ばれます。
    ///
    /// 責務: 登録画面への移行時に終了が呼ばれることを確認します。
    func testRegistrationPromptNotifiesBeginAndEndOnce() async throws {
        let model = try await signedInModel(port: ScriptedVehicleIdentificationPort(result: .success(Self.snapshot(vin: Self.vin))))

        try await identify(model)

        XCTAssertEqual(model.state.phase, .confirmingIdentification)
        XCTAssertEqual(events, ["willBegin", "identify", "didEnd"])
    }

    /// 識別の失敗(型付きエラー・取り消し・その他のエラー)でも、開始と終了が1回ずつ呼ばれます。
    ///
    /// 責務: 失敗の種類ごとに終了が1回呼ばれることを確認します。
    func testIdentificationFailuresNotifyBeginAndEndOnce() async throws {
        let failures: [any Error] = [
            VehicleIdentificationError.connectionFailed,
            VehicleIdentificationError.stageFailed(.adapterReset, .responseTimedOut),
            CancellationError(),
            VehicleRecordingTestError.vehicleLoadFailed,
        ]
        for failure in failures {
            events = []
            let model = try await signedInModel(port: ScriptedVehicleIdentificationPort(result: .failure(failure)))
            try await identify(model)
            XCTAssertEqual(model.state.phase, .failed, "\(failure)")
            XCTAssertEqual(events, ["willBegin", "identify", "didEnd"], "\(failure)")
        }
    }

    /// 未サインインの識別要求では、開始も終了も呼ばれません。
    ///
    /// 責務: 識別が行われない要求で手動使用が始まらないことを確認します。
    func testSignedOutRequestDoesNotNotify() async throws {
        let port = ScriptedVehicleIdentificationPort(result: .success(Self.snapshot(vin: Self.vin)))
        port.identificationDidStart = { [weak self] in self?.events.append("identify") }
        let model = VehicleManagementModel(
            state: VehicleManagementState(),
            repository: repository,
            identifyForConnection: IdentifyVehicleForConnectionUseCase(identification: port),
            photoImporter: ObservedVINRegistrationPhotoImportStub(),
            connectionIdentificationWillBegin: { [weak self] in self?.events.append("willBegin") },
            connectionIdentificationDidEnd: { [weak self] in self?.events.append("didEnd") }
        )

        model.send(.identifyRequested(Self.endpoint))
        try await BLEBoundedWaiter.settle()

        XCTAssertTrue(events.isEmpty)
    }

    /// 識別中に重ねて識別を要求しても、開始と終了は1回ずつです。
    ///
    /// 責務: 保留中の識別へ2回目の要求を送り、識別完了後の呼び出しを確認します。
    func testDuplicateRequestWhileIdentifyingNotifiesOnce() async throws {
        let port = ScriptedVehicleIdentificationPort(result: .success(Self.snapshot(vin: Self.vin)))
        let gate = AdapterLinkSupervisionScriptedResponses<Bool>()
        port.gate = gate
        gates.append(gate)
        let model = try await signedInModel(port: port)
        model.send(.identifyRequested(Self.endpoint))
        try await BLEBoundedWaiter.waitUntil("識別の保留") { gate.pendingCount == 1 }

        model.send(.identifyRequested(Self.endpoint))
        try await BLEBoundedWaiter.settle()
        gate.resumeOldest(with: .success(true))
        try await BLEBoundedWaiter.waitUntil("識別の終了") { events.contains("didEnd") }
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(events.filter { $0 == "willBegin" }.count, 1)
        XCTAssertEqual(events.filter { $0 == "didEnd" }.count, 1)
        XCTAssertEqual(port.callCount, 1)
    }
}

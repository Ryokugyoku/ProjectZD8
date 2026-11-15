import Foundation
import XCTest
@testable import ProjectZD8

/// `VehicleRecordingCoordinator` を実際の接続セッションモデルと車両照合に結び付け、出力を記録するテスト用の組み立てです。
///
/// 出力(テレメトリ開始・停止、監視への記録終了、手動使用の開始・終了)と接続セッションの保存は、
/// 起きた順に `events` へ文字列で記録します。
@MainActor
final class VehicleRecordingCoordinatorHarness {
    /// サインイン中として使うアカウント識別子です。
    static let account = "account-unit6"

    /// 記録に使う接続終端です。
    static let endpoint = OBDConnectionEndpoint(
        transport: .bluetoothLowEnergy,
        systemIdentifier: "6F1D2C3B-0000-4000-8000-00000000000A",
        displayName: "Adapter A"
    )

    /// 常駐リンクが初期化時に判定したアダプター判定結果です。
    static let evidence = AcquisitionAdapterProbeEvidence(chipFamily: .stn, monitorProbeOutcome: .framesReceived)

    /// 接続セッションの保存先 spy です。
    let sessionRepository = SavingConnectionSessionRepositorySpy()

    /// 登録済み車両の保存先 fake です。
    let vehicleRepository = AccountScopedVehicleRepositoryFake()

    /// 調停役の診断ポートの spy です。
    let diagnostics = VehicleRecordingDiagnosticsSpy()

    /// 実際の接続セッションモデルです。
    let lifecycle: ConnectionSessionLifecycleModel

    /// 検証対象の調停役です(照合処理が `self` を参照するため、生成の最後に設定します)。
    private(set) var coordinator: VehicleRecordingCoordinator!

    /// 車両照合に使うアカウント識別子です。`nil` は未サインインです。
    var lookupAccount: String?

    /// 設定されている場合、車両照合はこの台本の応答を待ってから照合します(照合中の状態を作るため)。
    var lookupGate: AdapterLinkSupervisionScriptedResponses<Bool>?

    /// 出力と保存の発生順です。
    private(set) var events: [String] = []

    /// テレメトリへ渡された開始要求です。
    private(set) var telemetryRequests: [VehicleRecordingStartRequest] = []

    /// テレメトリ停止の呼び出し回数です。
    private(set) var stopTelemetryCount = 0

    /// 監視へ記録終了を伝えた回数です。
    private(set) var finishCount = 0

    /// 監視へ返された記録終了の理由を、返された順に記録します。
    private(set) var finishReasons: [ConnectionSessionEndReason?] = []

    /// 監視へ手動使用の開始を伝えた回数です。
    private(set) var manualUseBeganCount = 0

    /// 監視へ手動使用の終了を伝えた回数です。
    private(set) var manualUseEndedCount = 0

    /// 調停役と依存を組み立て、全出力を記録先へ結び付けます。
    ///
    /// 責務: 実際の `StartVehicleRecordingSessionUseCase` と `FindRegisteredVehicleByVINUseCase` を使う調停役を作ります。
    /// - Parameter connectsTelemetry: `false` ならテレメトリ開始の出力を設定しません(開始手段なし)。
    init(connectsTelemetry: Bool = true) {
        lifecycle = ConnectionSessionLifecycleModel(repository: sessionRepository)
        let find = FindRegisteredVehicleByVINUseCase(repository: vehicleRepository)
        coordinator = VehicleRecordingCoordinator(
            startSession: StartVehicleRecordingSessionUseCase(lifecycle: lifecycle),
            findVehicle: { [weak self] vin in
                if let gate = self?.lookupGate { _ = try await gate.next() }
                return try await find.execute(vin: vin, accountIdentifier: self?.lookupAccount)
            },
            diagnostics: diagnostics
        )
        sessionRepository.saveDidSucceed = { [weak self] session in self?.events.append(Self.label(of: session)) }
        connectOutputs(connectsTelemetry: connectsTelemetry)
    }

    /// 調停役の出力クロージャを記録先へ結び付けます。
    ///
    /// 責務: テレメトリ開始・停止、記録終了、手動使用の開始・終了を回数と順序へ記録します。
    /// - Parameter connectsTelemetry: テレメトリ開始の出力を設定するかどうか。
    private func connectOutputs(connectsTelemetry: Bool) {
        if connectsTelemetry {
            coordinator.startTelemetry = { [weak self] request in
                self?.telemetryRequests.append(request)
                self?.events.append("telemetry.start")
            }
        }
        coordinator.stopTelemetry = { [weak self] _ in
            self?.stopTelemetryCount += 1
            self?.events.append("telemetry.stop")
        }
        coordinator.supervisedRecordingDidFinish = { [weak self] reason in
            self?.finishCount += 1
            self?.finishReasons.append(reason)
            self?.events.append("supervision.finish")
        }
        coordinator.manualAdapterUseDidBegin = { [weak self] in
            self?.manualUseBeganCount += 1
            self?.events.append("manual.began")
        }
        coordinator.manualAdapterUseDidEnd = { [weak self] in
            self?.manualUseEndedCount += 1
            self?.events.append("manual.ended")
        }
    }

    /// 保存されたセッションを手順名へ変換します。
    ///
    /// 責務: 終了・車両確定・観測VIN・開始のどの保存かを1語で表します。
    /// - Parameter session: 保存されたセッション。
    /// - Returns: `session.end` / `session.vehicle` / `session.vin` / `session.start` のいずれか。
    private static func label(of session: ConnectionSession) -> String {
        if session.endedAt != nil { return "session.end" }
        if session.vehicle != nil { return "session.vehicle" }
        if session.observedVIN != nil { return "session.vin" }
        return "session.start"
    }

    /// 接続セッションと車両照合をサインイン中のアカウントへ向けます。
    ///
    /// 責務: 接続セッションのアカウントと照合のアカウントを同じ識別子にします。
    func signIn() {
        lookupAccount = Self.account
        lifecycle.send(.accountIdentifierChanged(Self.account))
    }

    /// サインイン中アカウントの登録済み車両を設定します。
    ///
    /// 責務: 照合の対象になる車両一覧を置き換えます。
    /// - Parameter vehicles: 登録済み車両。
    func register(_ vehicles: [VehicleProfile]) {
        vehicleRepository.vehiclesByAccount[Self.account] = vehicles
    }

    /// 常駐リンクの記録開始要求を作ります。
    ///
    /// 責務: 共通の終端とアダプター判定結果に、指定VINを組み合わせます。
    /// - Parameter vin: 常駐リンクが読み取ったVIN。
    /// - Returns: 記録開始要求。
    static func residentRequest(vin: String?) -> AdapterLinkRecordingStartRequest {
        AdapterLinkRecordingStartRequest(endpoint: endpoint, vin: vin, adapterProbeEvidence: evidence)
    }

    /// 手動接続の記録開始要求を作ります。
    ///
    /// 責務: 指定車両で車両あり・観測VINなしの要求を作ります。
    /// - Parameter vehicle: 手動接続で確定した車両。
    /// - Returns: 記録開始要求。
    static func manualRequest(vehicle: VehicleProfile) -> VehicleRecordingStartRequest {
        VehicleRecordingStartRequest(
            endpoint: endpoint, vehicle: vehicle, observedVIN: nil, vehicleModelCode: nil, adapterProbeEvidence: nil
        )
    }

    /// 常駐リンクの記録開始を要求し、記録中になるか終了が伝わるまで上限付きで待ちます。
    ///
    /// 責務: 非同期の車両照合を含む開始手順の完了を待ちます。
    /// - Parameter vin: 常駐リンクが読み取ったVIN。
    func requestResidentStart(vin: String?, file: StaticString = #filePath, line: UInt = #line) async throws {
        let finishes = finishCount
        coordinator.requestRecordingStart(Self.residentRequest(vin: vin))
        try await BLEBoundedWaiter.waitUntil("常駐リンクの記録開始の決着", file: file, line: line) {
            coordinator.phase == .recording || finishCount > finishes
        }
    }

    /// 照合を止めた状態で常駐リンクの記録開始を要求し、照合が待機に入るまで待ちます。
    ///
    /// 責務: 調停役が照合中(`resolvingVehicle`)に留まる状態を作ります。
    /// - Parameter vin: 常駐リンクが読み取ったVIN。
    /// - Returns: 照合を進めるための台本。
    func requestResidentStartHoldingLookup(
        vin: String?, file: StaticString = #filePath, line: UInt = #line
    ) async throws -> AdapterLinkSupervisionScriptedResponses<Bool> {
        let gate = AdapterLinkSupervisionScriptedResponses<Bool>()
        lookupGate = gate
        coordinator.requestRecordingStart(Self.residentRequest(vin: vin))
        try await BLEBoundedWaiter.waitUntil("照合の待機", file: file, line: line) { gate.pendingCount == 1 }
        XCTAssertEqual(coordinator.phase, .resolvingVehicle, file: file, line: line)
        return gate
    }

    /// App がテレメトリの終了通知で行う処理を再現します(接続セッションの終了と調停役への終了通知)。
    ///
    /// 責務: `IOSApplicationRoot` の `sessionDidEnd` 配線と同じ順で終了を伝えます。
    /// - Parameter reason: テレメトリの終了理由。
    func telemetryDidEnd(reason: ConnectionSessionEndReason) {
        lifecycle.send(.endRequested(reason))
        coordinator.telemetryDidEnd(reason: reason)
    }
}

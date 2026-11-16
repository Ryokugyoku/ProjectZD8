import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase` を fake のリンク・ポート・時計で組み立て、仕様の段階まで進める手段です。
///
/// 待機はすべて `BLEBoundedWaiter` の回数上限付きで、上限を超えたら `XCTFail` します。
@MainActor
final class AdapterLinkSupervisionHarness {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 常駐リンクの fake です。
    let link = AdapterLinkFake()
    /// 既定アダプター設定の保存境界の fake です。
    let preferenceStore: AdapterLinkSupervisionDefaultAdapterPreferenceStore
    /// アダプター初期化の fake です。
    let initialization = AdapterLinkInitializationFake()
    /// 車両確認の fake です。
    let vehicleResponse = VehicleResponseConfirmationFake()
    /// VIN読取の fake です。
    let vinReader = VehicleIdentificationNumberReaderFake()
    /// 車両検知通知の spy です。
    let notifications = VehicleDetectionNotificationSpy()
    /// 自動記録設定の保存境界の fake です。
    let automaticRecording: AutomaticRecordingPreferenceFake
    /// 記録の開始・停止の spy です。
    let recordingControl = AdapterLinkRecordingControlSpy()
    /// 監視の時計の fake です。
    let clock = AdapterLinkSupervisionClockFake(now: AdapterLinkSupervisionFixtures.referenceDate)
    /// 検証対象の監視ユースケースです。
    let useCase: AdapterLinkSupervisionUseCase

    /// `stateDidChange` で受け取った状態です(受け取り順)。
    private(set) var observedStates: [AdapterLinkSupervisionState] = []

    /// 既定アダプター設定と自動記録設定を指定して組み立てます。
    ///
    /// 責務: 全ての fake を注入した監視ユースケースを生成し、状態変化の記録を結び付けます。
    /// - Parameters:
    ///   - defaultAdapter: 保存済みの既定アダプター設定。
    ///   - isAutomaticRecordingEnabled: 自動記録設定の初期値。
    init(defaultAdapter: DefaultAdapterPreference? = AdapterLinkSupervisionFixtures.blePreference, isAutomaticRecordingEnabled: Bool = false) {
        preferenceStore = AdapterLinkSupervisionDefaultAdapterPreferenceStore(preference: defaultAdapter)
        automaticRecording = AutomaticRecordingPreferenceFake(isEnabled: isAutomaticRecordingEnabled)
        useCase = AdapterLinkSupervisionUseCase(
            link: link,
            defaultAdapterPreference: DefaultAdapterPreferenceUseCase(preferencePort: preferenceStore),
            initialization: initialization,
            vehicleResponse: vehicleResponse,
            vinReader: vinReader,
            notifications: notifications,
            automaticRecordingPreference: automaticRecording,
            recordingControl: recordingControl,
            clock: clock
        )
        useCase.stateDidChange = { [weak self] state in self?.observedStates.append(state) }
    }

    /// 保留中の全ての非同期呼び出しを終わらせます。テストの終了時に呼びます。
    ///
    /// 責務: 再開されない継続を残さないよう、全 fake の保留を `CancellationError` で終わらせます。
    func finishAllPending() {
        initialization.responses.failAllPending()
        vehicleResponse.responses.failAllPending()
        vinReader.responses.failAllPending()
        clock.sleeps.failAllPending()
    }

    /// 条件が成り立つまで回数上限付きで待ちます。
    ///
    /// 責務: `BLEBoundedWaiter` へ委ね、上限超過時は呼び出し元の行で失敗させたうえで throw し、以降の手順(繰り返しを含む)を打ち切ります。
    /// - Parameters:
    ///   - description: 待機内容。
    ///   - condition: 待つ条件。
    /// - Returns: 常に `true`(成り立たなければ戻らずに throw します)。
    /// - Throws: 上限内に成り立たなかった場合は `AdapterLinkBoundedAwaitTimeout`。
    @discardableResult
    func wait(
        _ description: String, file: StaticString = #filePath, line: UInt = #line, until condition: () -> Bool
    ) async throws -> Bool {
        guard try await BLEBoundedWaiter.waitUntil(description, file: file, line: line, condition: condition) else {
            throw AdapterLinkBoundedAwaitTimeout(description: description)
        }
        return true
    }

    /// サインイン済みで監視を開始し、リンクの開始まで進めます。
    ///
    /// 責務: 認証状態の反映と `start()` を順に呼びます。
    func startSignedIn() {
        useCase.authenticationDidChange(isSignedIn: true)
        useCase.start()
    }

    /// リンクを `ready` にして初期化の呼び出しまで進めます(初期化の結果は保留のまま)。。
    ///
    /// 責務: 接続手順を経て `ready` を流し、初期化中になり初期化が1件保留されるまで待ちます。
    func makeLinkReady(file: StaticString = #filePath, line: UInt = #line) async throws {
        let calls = initialization.responses.callCount
        link.emit(.connecting)
        link.emit(.ready)
        try await wait("初期化の呼び出し", file: file, line: line) { initialization.responses.callCount == calls + 1 }
    }

    /// 初期化を成功させ、最初の車両確認が保留されるまで進めます。
    ///
    /// 責務: 初期化の保留へ判定結果を渡し、確認中になり確認が1件保留されるまで待ちます。
    /// - Parameter evidence: 初期化で返す判定結果。
    func finishInitialization(
        with evidence: AcquisitionAdapterProbeEvidence = AdapterLinkSupervisionFixtures.evidence,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let confirmations = vehicleResponse.timeouts.count
        initialization.responses.resumeOldest(with: .success(evidence), file: file, line: line)
        try await wait("最初の車両確認の呼び出し", file: file, line: line) {
            vehicleResponse.timeouts.count == confirmations + 1
        }
    }

    /// 開始からリンク `ready`・初期化成功を経て、最初の車両確認が保留される段階まで進めます。
    ///
    /// 責務: 車両確認中の段階を1回の呼び出しで用意します。
    func driveToConfirming(file: StaticString = #filePath, line: UInt = #line) async throws {
        startSignedIn()
        try await makeLinkReady(file: file, line: line)
        try await finishInitialization(file: file, line: line)
    }

    /// 保留中の車両確認へ無応答を返し、次の再確認の待機が保留されるまで進めます。
    ///
    /// 責務: 無応答の後に待機が1件増えるまで待ちます。
    func answerNoResponseAndWaitForSleep(file: StaticString = #filePath, line: UInt = #line) async throws {
        let sleeps = clock.requestedDurations.count
        vehicleResponse.responses.resumeOldest(with: .success(.noResponse), file: file, line: line)
        try await wait("再確認の待機", file: file, line: line) {
            clock.requestedDurations.count == sleeps + 1
        }
    }

    /// 車両確認へ応答ありを返し、VIN読取の呼び出しが保留されるまで進めます。
    ///
    /// 責務: 応答ありの後にVIN読取が1件保留されるまで待ちます。
    func answerRespondingAndWaitForVINRead(file: StaticString = #filePath, line: UInt = #line) async throws {
        let reads = vinReader.responses.callCount
        vehicleResponse.responses.resumeOldest(with: .success(.responding), file: file, line: line)
        try await wait("VIN読取の呼び出し", file: file, line: line) { vinReader.responses.callCount == reads + 1 }
    }

    /// 車両確認中から応答あり・VIN読取完了を経て、検知済みの記録開始操作待ちまで進めます(自動記録オフ前提)。
    ///
    /// 責務: 「車両を検知しました」通知が1件提示されるまで待ちます。
    /// - Parameter vin: VIN読取で返す値。
    func driveToAwaitingRecordingStart(vin: String? = AdapterLinkSupervisionFixtures.vin, file: StaticString = #filePath, line: UInt = #line) async throws {
        try await driveToConfirming(file: file, line: line)
        try await answerRespondingAndWaitForVINRead(file: file, line: line)
        vinReader.responses.resumeOldest(with: .success(vin), file: file, line: line)
        try await wait("検知通知の提示", file: file, line: line) { notifications.presentedVehicleDetectedVINs.count == 1 }
    }

    /// 検知済みから[記録開始]を選び、記録中まで進めます。
    ///
    /// 責務: 記録開始要求が1件出て記録中になるまで待ちます。
    func driveToRecording(file: StaticString = #filePath, line: UInt = #line) async throws {
        try await driveToAwaitingRecordingStart(file: file, line: line)
        useCase.recordingStartSelected()
        try await wait("記録中", file: file, line: line) {
            if case .recording = useCase.state { return recordingControl.startRequests.count == 1 }
            return false
        }
    }

    /// 現在の状態が記録中かどうかです。
    var isRecording: Bool {
        if case .recording = useCase.state { return true }
        return false
    }

    /// 現在の状態が車両確認中で、指定した段階かどうかを返します。
    ///
    /// 責務: 確認中の段階(低頻度確認中・休止中)を判定します。
    /// - Parameter phase: 期待する段階。
    /// - Returns: 一致すれば `true`。
    func isConfirming(_ phase: AdapterLinkVehicleConfirmationPhase) -> Bool {
        if case let .confirmingVehicle(confirmation) = useCase.state { return confirmation.phase == phase }
        return false
    }
}

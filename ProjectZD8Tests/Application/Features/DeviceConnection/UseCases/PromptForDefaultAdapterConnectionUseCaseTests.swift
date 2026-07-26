import XCTest
@testable import ProjectZD8

/// 既定BLE到来を通知承認付き接続要求へ変換するユースケースを検証します。
@MainActor
final class PromptForDefaultAdapterConnectionUseCaseTests: XCTestCase {
    /// 通知許可後に既定BLE監視を開始し、了承された終端を接続要求へ渡すことを検証します。
    ///
    /// 責務: 許可済みBLE到来から接続了承までの正常経路を確認します。
    func testStartMonitorsBLEAndForwardsAcceptedEndpoint() async {
        let preference = makePreference(transport: .bluetoothLowEnergy)
        let monitor = DefaultAdapterArrivalMonitorSpy()
        let prompt = DefaultAdapterConnectionPromptSpy(isAuthorized: true)
        var requestedEndpoint: OBDConnectionEndpoint?
        let useCase = makeUseCase(
            preference: preference,
            monitor: monitor,
            prompt: prompt
        ) {
            requestedEndpoint = $0
        }

        useCase.start()
        await Task.yield()
        let endpoint = OBDConnectionEndpoint(
            transport: .bluetoothLowEnergy,
            systemIdentifier: preference.systemIdentifier,
            displayName: preference.displayName
        )
        monitor.arrival?(endpoint)
        prompt.acceptance?(endpoint)

        XCTAssertEqual(monitor.monitoredPreference, preference)
        XCTAssertEqual(prompt.presentedEndpoint, endpoint)
        XCTAssertEqual(requestedEndpoint, endpoint)
    }

    /// 通知が拒否されている場合にBLE監視を開始しないことを検証します。
    ///
    /// 責務: 通知不能状態がバックグラウンド監視を残さないことを確認します。
    func testStartDoesNotMonitorWhenNotificationsAreDenied() async {
        let monitor = DefaultAdapterArrivalMonitorSpy()
        let prompt = DefaultAdapterConnectionPromptSpy(isAuthorized: false)
        let useCase = makeUseCase(
            preference: makePreference(transport: .bluetoothLowEnergy),
            monitor: monitor,
            prompt: prompt
        ) { _ in }

        useCase.start()
        await Task.yield()

        XCTAssertNil(monitor.monitoredPreference)
        XCTAssertEqual(monitor.stopCallCount, 1)
    }

    /// Bluetooth Classic設定ではBLE到来監視を開始しないことを検証します。
    ///
    /// 責務: iPhoneのBLE専用自動確認がClassic終端へ誤適用されないことを確認します。
    func testStartIgnoresBluetoothClassicPreference() async {
        let monitor = DefaultAdapterArrivalMonitorSpy()
        let prompt = DefaultAdapterConnectionPromptSpy(isAuthorized: true)
        let useCase = makeUseCase(
            preference: makePreference(transport: .bluetoothClassic),
            monitor: monitor,
            prompt: prompt
        ) { _ in }

        useCase.start()
        await Task.yield()

        XCTAssertNil(monitor.monitoredPreference)
        XCTAssertEqual(prompt.prepareCallCount, 0)
    }

    /// 指定した依存関係で到来確認ユースケースを生成します。
    ///
    /// 責務: 1件のテストシナリオ用依存関係を検証対象へ注入します。
    /// - Parameters:
    ///   - preference: 読込時に返す既定設定。
    ///   - monitor: 到来監視Spy。
    ///   - prompt: 接続確認Spy。
    ///   - connectionRequested: 接続了承の通知先。
    /// - Returns: 注入済みの検証対象。
    private func makeUseCase(
        preference: DefaultAdapterPreference,
        monitor: DefaultAdapterArrivalMonitorSpy,
        prompt: DefaultAdapterConnectionPromptSpy,
        connectionRequested: @escaping @MainActor (OBDConnectionEndpoint) -> Void
    ) -> PromptForDefaultAdapterConnectionUseCase {
        PromptForDefaultAdapterConnectionUseCase(
            defaultAdapterPreference: DefaultAdapterPreferenceUseCase(
                preferencePort: DefaultAdapterPreferencePortStub(preference: preference)
            ),
            arrivalMonitor: monitor,
            connectionPrompt: prompt,
            connectionRequested: connectionRequested
        )
    }

    /// 指定した物理終端の既定Bluetooth設定を生成します。
    ///
    /// 責務: BLEまたはClassicだけが異なる既定設定を1件構築します。
    /// - Parameter transport: 設定へ保持する物理終端。
    /// - Returns: 固定UUIDを持つ既定Bluetooth設定。
    private func makePreference(
        transport: OBDConnectionEndpoint.Transport
    ) -> DefaultAdapterPreference {
        DefaultAdapterPreference(
            adapterID: "bluetooth:test",
            transportMode: .bluetooth,
            connectionTransport: transport,
            displayName: "Test Adapter",
            systemIdentifier: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )
    }
}

/// 到来確認テストへ固定の既定設定を返す保存境界です。
private final class DefaultAdapterPreferencePortStub: DefaultAdapterPreferencePort {
    /// 読込時に返す既定設定です。
    private let preference: DefaultAdapterPreference

    /// 固定設定を注入して生成します。
    ///
    /// 責務: 1件の既定設定を読込結果として固定します。
    /// - Parameter preference: 読込時に返す設定。
    init(preference: DefaultAdapterPreference) {
        self.preference = preference
    }

    /// 注入済みの既定設定を返します。
    ///
    /// 責務: 既定設定読込要求へ固定値で応答します。
    /// - Returns: 初期化時に注入された設定。
    func load() -> DefaultAdapterPreference? {
        preference
    }

    /// テストでは使用しない保存要求を受け取ります。
    ///
    /// 責務: 保存副作用を持たないテスト境界を提供します。
    /// - Parameter preference: テストでは保持しない設定。
    func save(_ preference: DefaultAdapterPreference) {}
}

/// 既定BLE到来監視の呼出しと通知先を記録します。
@MainActor
private final class DefaultAdapterArrivalMonitorSpy: DefaultAdapterArrivalMonitoring {
    /// 最後に監視要求された既定設定です。
    private(set) var monitoredPreference: DefaultAdapterPreference?

    /// 監視停止の呼出し回数です。
    private(set) var stopCallCount = 0

    /// 到来をテストから送信する処理です。
    private(set) var arrival: (@MainActor (OBDConnectionEndpoint) -> Void)?

    /// 監視対象と到来通知先を記録します。
    ///
    /// 責務: 1回の監視開始要求をテスト観測状態へ保存します。
    /// - Parameters:
    ///   - preference: 監視対象の既定設定。
    ///   - arrival: 到来時の通知先。
    func startMonitoring(
        preference: DefaultAdapterPreference,
        arrival: @escaping @MainActor (OBDConnectionEndpoint) -> Void
    ) {
        monitoredPreference = preference
        self.arrival = arrival
    }

    /// 監視停止の呼出しを記録します。
    ///
    /// 責務: 1回の停止要求を呼出し回数へ反映します。
    func stopMonitoring() {
        stopCallCount += 1
        monitoredPreference = nil
        arrival = nil
    }
}

/// 接続確認通知の許可、提示、了承を記録します。
@MainActor
private final class DefaultAdapterConnectionPromptSpy: DefaultAdapterConnectionPrompting {
    /// 準備時に返す通知許可状態です。
    private let isAuthorized: Bool

    /// 通知準備の呼出し回数です。
    private(set) var prepareCallCount = 0

    /// 最後に提示要求された接続終端です。
    private(set) var presentedEndpoint: OBDConnectionEndpoint?

    /// 接続了承をテストから送信する処理です。
    private(set) var acceptance: (@MainActor (OBDConnectionEndpoint) -> Void)?

    /// 固定通知許可状態を注入して生成します。
    ///
    /// 責務: 1件の通知許可結果を接続確認テストへ固定します。
    /// - Parameter isAuthorized: 準備時に返す許可状態。
    init(isAuthorized: Bool) {
        self.isAuthorized = isAuthorized
    }

    /// 通知先を記録して固定許可状態を返します。
    ///
    /// 責務: 1回の通知準備要求を観測して固定許可結果へ変換します。
    /// - Parameter acceptance: 接続了承時の通知先。
    /// - Returns: 初期化時に指定された通知許可状態。
    func prepare(
        acceptance: @escaping @MainActor (OBDConnectionEndpoint) -> Void
    ) async -> Bool {
        prepareCallCount += 1
        self.acceptance = acceptance
        return isAuthorized
    }

    /// 提示要求された接続終端を記録します。
    ///
    /// 責務: 1件の通知提示要求をテスト観測状態へ保存します。
    /// - Parameter endpoint: 提示対象の接続終端。
    func present(endpoint: OBDConnectionEndpoint) {
        presentedEndpoint = endpoint
    }
}

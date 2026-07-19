import XCTest
@testable import ProjectZD8

/// アカウント設定モデルのスコープ分離、保存、同期反映を検証します。
@MainActor
final class AccountSettingsModelTests: XCTestCase {
    /// 認証済みアカウントの保存設定を初期表示へ復元することを検証します。
    ///
    /// 責務: アカウント識別子の通知が対応する言語と外観だけをモデルへ読み込むことを確認します。
    func testAccountActivationRestoresSavedSettings() {
        let store = AccountSettingsStorePortFake()
        store.savedSettings["user-a"] = AccountSettings(language: .english, appearance: .dark)
        let model = makeModel(store: store)

        model.send(.accountIdentifierChanged("user-a"))

        XCTAssertEqual(model.settings, AccountSettings(language: .english, appearance: .dark))
        XCTAssertEqual(store.observedAccountIdentifier, "user-a")
    }

    /// 言語と外観の変更を現在のアカウントだけへ保存することを検証します。
    ///
    /// 責務: 2件の設定操作をConnection情報を含まない1件のアカウント設定として保存します。
    func testSelectionChangesPersistForActiveAccount() {
        let store = AccountSettingsStorePortFake()
        let model = makeModel(store: store)
        model.send(.accountIdentifierChanged("user-a"))

        model.send(.languageSelected(.spanish))
        model.send(.appearanceSelected(.light))

        XCTAssertEqual(
            store.savedSettings["user-a"],
            AccountSettings(language: .spanish, appearance: .light)
        )
        XCTAssertEqual(store.saveCount, 2)
    }

    /// 別アカウントへ切り替えた際に以前の設定を引き継がないことを検証します。
    ///
    /// 責務: アカウントスコープ変更が新しい識別子固有の設定だけを表示状態へ反映します。
    func testAccountSwitchKeepsSettingsIsolated() {
        let store = AccountSettingsStorePortFake()
        store.savedSettings["user-a"] = AccountSettings(language: .english, appearance: .dark)
        store.savedSettings["user-b"] = AccountSettings(language: .spanish, appearance: .light)
        let model = makeModel(store: store)

        model.send(.accountIdentifierChanged("user-a"))
        model.send(.accountIdentifierChanged("user-b"))

        XCTAssertEqual(model.settings, AccountSettings(language: .spanish, appearance: .light))
        XCTAssertEqual(store.stopObservationCount, 2)
    }

    /// 別端末から届いた設定を起動中の表示へ反映することを検証します。
    ///
    /// 責務: 現在のアカウントに対する同期変更をモデルの言語と外観へ反映します。
    func testExternalSettingsUpdateCurrentState() {
        let store = AccountSettingsStorePortFake()
        let model = makeModel(store: store)
        model.send(.accountIdentifierChanged("user-a"))

        store.sendExternal(AccountSettings(language: .english, appearance: .dark))

        XCTAssertEqual(model.settings, AccountSettings(language: .english, appearance: .dark))
    }

    /// テスト対象モデルを指定保存境界で生成します。
    ///
    /// 責務: 1件の設定モデルテスト用依存関係を構築します。
    /// - Parameter store: 保存、復元、同期通知を記録するFake。
    /// - Returns: Fakeを注入したアカウント設定モデル。
    private func makeModel(store: AccountSettingsStorePortFake) -> AccountSettingsModel {
        AccountSettingsModel(
            settings: AccountSettings(),
            useCase: AccountSettingsUseCase(store: store)
        )
    }
}

/// アカウント設定モデルテストで保存と同期通知を記録します。
@MainActor
private final class AccountSettingsStorePortFake: AccountSettingsStorePort {
    /// アカウント識別子ごとに保持するテスト設定です。
    var savedSettings: [String: AccountSettings] = [:]

    /// 保存要求を受け取った回数です。
    private(set) var saveCount = 0

    /// 現在監視しているアカウント識別子です。
    private(set) var observedAccountIdentifier: String?

    /// 監視終了要求を受け取った回数です。
    private(set) var stopObservationCount = 0

    /// 外部変更として設定を返す処理です。
    private var receive: ((AccountSettings) -> Void)?

    /// 指定アカウントのテスト設定を返します。
    ///
    /// 責務: 1件のアカウント識別子に対応するFake設定を復元します。
    /// - Parameter accountIdentifier: 読込対象のアカウント識別子。
    /// - Returns: Fakeに保存されている設定。
    func load(for accountIdentifier: String) -> AccountSettings? {
        savedSettings[accountIdentifier]
    }

    /// 指定アカウントへテスト設定を保存します。
    ///
    /// 責務: 1件の保存要求をアカウント別Fake領域へ記録します。
    /// - Parameters:
    ///   - settings: 保存要求された設定。
    ///   - accountIdentifier: 保存対象のアカウント識別子。
    func save(_ settings: AccountSettings, for accountIdentifier: String) {
        saveCount += 1
        savedSettings[accountIdentifier] = settings
    }

    /// 指定アカウントの外部変更受信処理を保持します。
    ///
    /// 責務: 1件のアカウント監視要求をテストから呼出可能な状態へ記録します。
    /// - Parameters:
    ///   - accountIdentifier: 監視対象のアカウント識別子。
    ///   - receive: 外部設定を返す処理。
    func startObserving(
        for accountIdentifier: String,
        receive: @escaping (AccountSettings) -> Void
    ) {
        observedAccountIdentifier = accountIdentifier
        self.receive = receive
    }

    /// 現在のテスト監視を終了します。
    ///
    /// 責務: 監視終了を記録して外部変更受信処理を破棄します。
    func stopObserving() {
        stopObservationCount += 1
        observedAccountIdentifier = nil
        receive = nil
    }

    /// 指定設定を別端末からの変更として通知します。
    ///
    /// 責務: 1件の同期設定を現在のテスト受信処理へ渡します。
    /// - Parameter settings: 外部変更として通知する設定。
    func sendExternal(_ settings: AccountSettings) {
        receive?(settings)
    }
}

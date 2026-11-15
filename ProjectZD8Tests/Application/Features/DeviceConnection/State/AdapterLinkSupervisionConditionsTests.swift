import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionConditions` の稼働条件とリンク準備の判定を検証します。
@MainActor
final class AdapterLinkSupervisionConditionsTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 開始済み・サインイン済み・既定アダプターがBLEの時だけ接続対象を返します。
    ///
    /// 責務: 3条件を全て満たした場合に既定アダプター設定がそのまま接続対象になることを確認します。
    func testOperatingPreferenceIsDefaultWhenAllConditionsHold() {
        XCTAssertEqual(F.conditions(defaultAdapterPreference: F.blePreference).operatingPreference, F.blePreference)
        XCTAssertEqual(
            F.conditions(defaultAdapterPreference: F.otherBLEPreference).operatingPreference,
            F.otherBLEPreference
        )
    }

    /// 監視が開始されていなければ接続対象はありません。
    ///
    /// 責務: `start()` 前・`stop()` 後の条件では接続対象が `nil` になることを確認します。
    func testOperatingPreferenceIsNilWhenSupervisionIsNotStarted() {
        XCTAssertNil(F.conditions(isSupervisionStarted: false).operatingPreference)
    }

    /// 未サインインでは接続対象はありません。
    ///
    /// 責務: サインインしていない条件では既定アダプターがBLEでも接続対象が `nil` になることを確認します。
    func testOperatingPreferenceIsNilWhenSignedOut() {
        XCTAssertNil(F.conditions(isSignedIn: false).operatingPreference)
    }

    /// 既定アダプター未設定・Bluetooth Classic・シリアルでは接続対象はありません。
    ///
    /// 責務: BLE以外または未設定の既定アダプターが接続対象にならないことを確認します。
    func testOperatingPreferenceIsNilWithoutBLEDefaultAdapter() {
        XCTAssertNil(F.conditions(defaultAdapterPreference: nil).operatingPreference)
        XCTAssertNil(F.conditions(defaultAdapterPreference: F.classicPreference).operatingPreference)
        XCTAssertNil(F.conditions(defaultAdapterPreference: F.serialPreference).operatingPreference)
    }

    /// 接続対象はリンクの開始状態やリンク状態に左右されません。
    ///
    /// 責務: リンク未開始・切断中でも稼働条件だけで接続対象が決まることを確認します。
    func testOperatingPreferenceIgnoresLinkStateAndLinkPreference() {
        let conditions = F.conditions(linkPreference: nil, linkState: .disconnected(.bluetoothPoweredOff))
        XCTAssertEqual(conditions.operatingPreference, F.blePreference)
    }

    /// リンク開始済みかつ直前のリンク状態が `ready` の時だけリンク準備済みです。
    ///
    /// 責務: `isLinkReady` が真になる唯一の組み合わせを確認します。
    func testIsLinkReadyWhenLinkStartedAndReady() {
        XCTAssertTrue(F.conditions(linkPreference: F.blePreference, linkState: .ready).isLinkReady)
    }

    /// リンクを開始していなければ、リンク状態が `ready` でも準備済みではありません。
    ///
    /// 責務: 接続対象のないリンクの `ready` を準備済みとして扱わないことを確認します。
    func testIsLinkReadyIsFalseWithoutLinkPreference() {
        XCTAssertFalse(F.conditions(linkPreference: nil, linkState: .ready).isLinkReady)
    }

    /// `ready` 以外の全てのリンク状態では準備済みではありません。
    ///
    /// 責務: 未開始・広告待ち・接続中・探索中・切断の各状態で `false` になることを確認します。
    func testIsLinkReadyIsFalseForEveryNonReadyLinkState() {
        let states: [AdapterLinkState] = [
            .idle, .awaitingPeripheral, .connecting, .discovering,
            .disconnected(.peripheralDisconnected(errorDescription: nil)), .disconnected(.retryLimitExceeded),
        ]
        for state in states {
            XCTAssertFalse(F.conditions(linkState: state).isLinkReady, "\(state)")
        }
    }

    /// 稼働条件を満たさなくても、開始済みリンクが `ready` なら準備済みです。
    ///
    /// 責務: `isLinkReady` がリンクの事実だけを表し、稼働条件と独立であることを確認します。
    func testIsLinkReadyIsIndependentOfOperatingConditions() {
        XCTAssertTrue(F.conditions(isSignedIn: false, linkState: .ready).isLinkReady)
    }
}

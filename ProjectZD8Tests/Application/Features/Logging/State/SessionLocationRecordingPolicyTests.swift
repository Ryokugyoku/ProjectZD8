import XCTest
@testable import ProjectZD8

/// `SessionLocationRecordingPolicy` の判定を、上から順の評価と優先順位を含めて検証します。
final class SessionLocationRecordingPolicyTests: XCTestCase {
    private let policy = SessionLocationRecordingPolicy()

    /// 責務: 既定を「設定オン・正確・前面・取得可能」として判定します。
    private func decide(
        enabled: Bool = true,
        level: LocationAuthorizationLevel,
        precise: Bool = true,
        foreground: Bool = true,
        available: Bool = true
    ) -> SessionLocationRecordingDecision {
        policy.decision(
            isRecordingEnabled: enabled,
            permission: LocationPermission(level: level, isPreciseAccuracy: precise),
            isForeground: foreground,
            isLocationAvailable: available
        )
    }

    /// 責務: 期待する判定値を作ります。
    private func expected(_ acquires: Bool, _ kind: ConnectionSessionLocationEventKind) -> SessionLocationRecordingDecision {
        SessionLocationRecordingDecision(acquiresLocation: acquires, eventKind: kind)
    }

    /// 責務: 非対応の環境では設定に関わらず取得しないことを確かめます。
    func testUnsupportedPlatformIgnoresSetting() {
        XCTAssertEqual(decide(enabled: true, level: .unsupportedPlatform), expected(false, .unsupportedPlatform))
        XCTAssertEqual(decide(enabled: false, level: .unsupportedPlatform), expected(false, .unsupportedPlatform))
    }

    /// 責務: 設定オフなら許可が always でも取得しないことを確かめます。
    func testDisabledSettingDoesNotAcquire() {
        XCTAssertEqual(decide(enabled: false, level: .always), expected(false, .disabledBySetting))
        XCTAssertEqual(decide(enabled: false, level: .whenInUse), expected(false, .disabledBySetting))
    }

    /// 責務: 未確定・拒否・制限の許可では取得せず対応する事象になることを確かめます。
    func testUnauthorizedLevelsDoNotAcquire() {
        XCTAssertEqual(decide(level: .notDetermined), expected(false, .authorizationNotDetermined))
        XCTAssertEqual(decide(level: .denied), expected(false, .authorizationDenied))
        XCTAssertEqual(decide(level: .restricted), expected(false, .authorizationRestricted))
    }

    /// 責務: 使用中のみ許可で背面なら取得しないことを確かめます。
    func testWhenInUseInBackgroundDoesNotAcquire() {
        XCTAssertEqual(
            decide(level: .whenInUse, foreground: false),
            expected(false, .backgroundWithoutAlwaysAuthorization)
        )
    }

    /// 責務: 使用中のみ許可で前面なら取得することを確かめます。
    func testWhenInUseInForegroundAcquires() {
        XCTAssertEqual(decide(level: .whenInUse, foreground: true), expected(true, .recording))
    }

    /// 責務: 常に許可なら背面でも前面でも取得することを確かめます。
    func testAlwaysAcquiresInBackgroundAndForeground() {
        XCTAssertEqual(decide(level: .always, foreground: false), expected(true, .recording))
        XCTAssertEqual(decide(level: .always, foreground: true), expected(true, .recording))
    }

    /// 責務: 取得不可なら取得は続け、事象は locationUnavailable になることを確かめます。
    func testLocationUnavailableStillAcquires() {
        XCTAssertEqual(decide(level: .always, available: false), expected(true, .locationUnavailable))
        XCTAssertEqual(decide(level: .whenInUse, available: false), expected(true, .locationUnavailable))
    }

    /// 責務: 概略の位置のみなら取得し、recordingWithReducedAccuracy になることを確かめます。
    func testReducedAccuracyAcquiresWithReducedAccuracyEvent() {
        XCTAssertEqual(decide(level: .always, precise: false), expected(true, .recordingWithReducedAccuracy))
        XCTAssertEqual(decide(level: .whenInUse, precise: false), expected(true, .recordingWithReducedAccuracy))
    }

    /// 責務: 設定オフが拒否の許可より先に評価されることを確かめます。
    func testDisabledSettingTakesPrecedenceOverDenied() {
        XCTAssertEqual(decide(enabled: false, level: .denied), expected(false, .disabledBySetting))
    }

    /// 責務: 取得不可が概略の位置より先に評価されることを確かめます。
    func testUnavailableTakesPrecedenceOverReducedAccuracy() {
        XCTAssertEqual(
            decide(level: .always, precise: false, available: false),
            expected(true, .locationUnavailable)
        )
    }

    /// 責務: 使用中のみの背面が取得不可より先に評価されることを確かめます。
    func testBackgroundTakesPrecedenceOverUnavailable() {
        XCTAssertEqual(
            decide(level: .whenInUse, foreground: false, available: false),
            expected(false, .backgroundWithoutAlwaysAuthorization)
        )
    }

    /// 責務: 拒否・制限・未確定では前面かどうかや取得可否が結果を変えないことを確かめます。
    func testUnauthorizedIgnoresForegroundAndAvailability() {
        XCTAssertEqual(
            decide(level: .denied, foreground: false, available: false),
            expected(false, .authorizationDenied)
        )
        XCTAssertEqual(
            decide(level: .notDetermined, precise: false, foreground: false),
            expected(false, .authorizationNotDetermined)
        )
    }
}

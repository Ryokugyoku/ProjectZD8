import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionTiming` の定数と派生値を検証します。
final class AdapterLinkSupervisionTimingTests: XCTestCase {
    /// 本番の定数は確認窓10分・再確認間隔30秒です。
    ///
    /// 責務: 仕様の時間定数が `standard` に定義されていることを確認します。
    func testStandardUsesTenMinuteWindowAndThirtySecondInterval() {
        XCTAssertEqual(AdapterLinkSupervisionTiming.standard.vehicleConfirmationWindow, 600)
        XCTAssertEqual(AdapterLinkSupervisionTiming.standard.vehicleConfirmationInterval, 30)
    }

    /// 本番の定数では1窓あたりの確認は最初の確認を含めて20回までです。
    ///
    /// 責務: 時計が進まない場合の確認回数の上限が仕様の20回であることを確認します。
    func testStandardAllowsTwentyAttemptsPerWindow() {
        XCTAssertEqual(AdapterLinkSupervisionTiming.standard.maximumVehicleConfirmationAttempts, 20)
    }

    /// 本番の再確認間隔は30秒の待機時間へ変換されます。
    ///
    /// 責務: 待機ポートへ渡す `Duration` が30秒ちょうどであることを確認します。
    func testStandardIntervalDurationIsThirtySeconds() {
        XCTAssertEqual(AdapterLinkSupervisionTiming.standard.vehicleConfirmationIntervalDuration, .seconds(30))
    }

    /// 窓が間隔で割り切れる場合、回数の上限は窓の中に収まる確認回数と一致します。
    ///
    /// 責務: 90秒窓・30秒間隔(0・30・60秒の3回)で上限が3になることを確認します。
    func testAttemptsMatchConfirmationsFittingInDivisibleWindow() {
        let timing = AdapterLinkSupervisionTiming(vehicleConfirmationWindow: 90, vehicleConfirmationInterval: 30)
        XCTAssertEqual(timing.maximumVehicleConfirmationAttempts, 3)
    }

    /// 窓と間隔が等しい場合は最初の確認1回だけです。
    ///
    /// 責務: 境界値(窓=間隔)で上限が1になることを確認します。
    func testAttemptsIsOneWhenWindowEqualsInterval() {
        let timing = AdapterLinkSupervisionTiming(vehicleConfirmationWindow: 30, vehicleConfirmationInterval: 30)
        XCTAssertEqual(timing.maximumVehicleConfirmationAttempts, 1)
    }

    /// 窓が間隔より短くても最初の確認1回は行えます。
    ///
    /// 責務: 窓<間隔で上限が0にならず1になることを確認します。
    func testAttemptsIsAtLeastOneWhenWindowIsShorterThanInterval() {
        let timing = AdapterLinkSupervisionTiming(vehicleConfirmationWindow: 10, vehicleConfirmationInterval: 30)
        XCTAssertEqual(timing.maximumVehicleConfirmationAttempts, 1)
    }

    /// 間隔が0以下でも上限は有限の1回になり、再確認が無限に続きません。
    ///
    /// 責務: 不正な間隔(0・負)で上限が1になることを確認します。
    func testAttemptsIsOneForNonPositiveInterval() {
        let zero = AdapterLinkSupervisionTiming(vehicleConfirmationWindow: 600, vehicleConfirmationInterval: 0)
        let negative = AdapterLinkSupervisionTiming(vehicleConfirmationWindow: 600, vehicleConfirmationInterval: -5)
        XCTAssertEqual(zero.maximumVehicleConfirmationAttempts, 1)
        XCTAssertEqual(negative.maximumVehicleConfirmationAttempts, 1)
    }

    /// 秒数の端数はミリ秒単位の待機時間へ変換されます。
    ///
    /// 責務: 1.5秒の間隔が1500ミリ秒の `Duration` になることを確認します。
    func testIntervalDurationKeepsMilliseconds() {
        let timing = AdapterLinkSupervisionTiming(vehicleConfirmationWindow: 60, vehicleConfirmationInterval: 1.5)
        XCTAssertEqual(timing.vehicleConfirmationIntervalDuration, .milliseconds(1500))
    }
}

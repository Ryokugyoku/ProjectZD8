import XCTest
@testable import ProjectZD8

/// テスト用の手動単調時計の初期値と加算を検証します。
final class ManualMonotonicClockTests: XCTestCase {
    /// 初期値を指定しない時計は0から始まります。
    ///
    /// 責務: 既定の初期値が0であることを確認します。
    func testDefaultInitialValueIsZero() {
        XCTAssertEqual(ManualMonotonicClock().nowNanoseconds(), 0)
    }

    /// 指定した初期値がそのまま読めます。
    ///
    /// 責務: 初期値指定が現在値になることを確認します。
    func testInitialValueIsReturned() {
        XCTAssertEqual(ManualMonotonicClock(initialNanoseconds: 42).nowNanoseconds(), 42)
    }

    /// 進めた分だけ現在値が増えます。
    ///
    /// 責務: 1回の加算が初期値へ足されることを確認します。
    func testAdvanceAddsToInitialValue() {
        let clock = ManualMonotonicClock(initialNanoseconds: 100)
        clock.advance(byNanoseconds: 25)
        XCTAssertEqual(clock.nowNanoseconds(), 125)
    }

    /// 複数回の加算が累積し、進めない間は値が変わりません。
    ///
    /// 責務: 加算の累積と、読み取りだけでは進まないことを確認します。
    func testMultipleAdvancesAccumulateAndReadsDoNotAdvance() {
        let clock = ManualMonotonicClock()
        clock.advance(byNanoseconds: 1_000_000_000)
        clock.advance(byNanoseconds: 7)
        XCTAssertEqual(clock.nowNanoseconds(), 1_000_000_007)
        XCTAssertEqual(clock.nowNanoseconds(), 1_000_000_007)
    }
}

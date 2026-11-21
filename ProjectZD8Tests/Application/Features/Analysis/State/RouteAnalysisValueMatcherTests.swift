import Foundation
import XCTest
@testable import ProjectZD8

/// 位置の時刻に、最近傍の値を対応づける規則を検証します(設計書 §2.3。差 2.0 s 以下、等距離なら早い方)。
@MainActor
final class RouteAnalysisValueMatcherTests: XCTestCase {
    /// 既定(許容差 2.0 s)の検証対象です。
    private let matcher = RouteAnalysisValueMatcher()

    /// 値の列の中で、基準から `seconds` 秒後の値を引きます。
    ///
    /// 責務: 秒と値の組から列を作り、指定の時刻で対応づけた値を返します。
    /// - Parameters:
    ///   - seconds: 引く時刻(基準からの秒)。
    ///   - samples: 秒と値の組。
    ///   - matcher: 使う対応づけ。省略時は既定。
    /// - Returns: 対応づけた値。
    private func value(
        at seconds: TimeInterval,
        in samples: [(seconds: TimeInterval, value: Double)],
        matcher: RouteAnalysisValueMatcher? = nil
    ) -> Double? {
        let series = RouteAnalysisValueSeriesFixtures.series(samples)
        return (matcher ?? self.matcher).value(at: RouteAnalysisTimelinePointFixtures.base.addingTimeInterval(seconds), in: series)
    }

    /// 責務: 時刻が一致する値をそのまま返すことを確かめます。
    func testExactMatch() {
        XCTAssertEqual(value(at: 10, in: [(9, 1), (10, 2), (11, 3)]), 2)
    }

    /// 責務: 2つの値の間では近い方を返すことを確かめます。
    func testPicksNearestSample() {
        XCTAssertEqual(value(at: 10.4, in: [(10, 1), (11, 2)]), 1)
        XCTAssertEqual(value(at: 10.6, in: [(10, 1), (11, 2)]), 2)
    }

    /// 責務: 差がちょうど 2.0 s の値は、前側でも後ろ側でも採ることを確かめます。
    func testDifferenceAtToleranceIsAccepted() {
        XCTAssertEqual(value(at: 12, in: [(10, 5)]), 5)
        XCTAssertEqual(value(at: 8, in: [(10, 5)]), 5)
    }

    /// 責務: 差が 2.0 s の少し外側(2.001 s)なら、前側でも後ろ側でも `nil` になることを確かめます。
    func testDifferenceJustBeyondToleranceIsNil() {
        XCTAssertNil(value(at: 12.001, in: [(10, 5)]))
        XCTAssertNil(value(at: 7.999, in: [(10, 5)]))
    }

    /// 責務: 前後の値が等距離なら、時刻の早い方を返すことを確かめます。
    func testEquidistantPrefersEarlierSample() {
        XCTAssertEqual(value(at: 11, in: [(10, 1), (12, 2)]), 1)
    }

    /// 責務: 空の列では `nil` になることを確かめます。
    func testEmptySeriesGivesNil() {
        XCTAssertNil(value(at: 0, in: []))
    }

    /// 責務: 最初の値より前の時刻では、許容差の内なら最初の値、外なら `nil` になることを確かめます。
    func testBeforeFirstSample() {
        XCTAssertEqual(value(at: 8.5, in: [(10, 1), (20, 2)]), 1)
        XCTAssertNil(value(at: 7.5, in: [(10, 1), (20, 2)]))
    }

    /// 責務: 最後の値より後の時刻では、許容差の内なら最後の値、外なら `nil` になることを確かめます。
    func testAfterLastSample() {
        XCTAssertEqual(value(at: 21.5, in: [(10, 1), (20, 2)]), 2)
        XCTAssertNil(value(at: 22.5, in: [(10, 1), (20, 2)]))
    }

    /// 責務: 値の無い区間(前後とも 2 s より離れた時刻)では `nil` になることを確かめます。
    func testGapBetweenSamplesGivesNil() {
        XCTAssertNil(value(at: 15, in: [(10, 1), (20, 2)]))
    }

    /// 責務: 初期化で渡した許容差(0.5 s)が、内側(0.4 s)と外側(0.6 s)の判定に使われることを確かめます。
    func testCustomToleranceIsApplied() {
        let strict = RouteAnalysisValueMatcher(toleranceSeconds: 0.5)

        XCTAssertEqual(value(at: 10.4, in: [(10, 3)], matcher: strict), 3)
        XCTAssertNil(value(at: 10.6, in: [(10, 3)], matcher: strict))
    }

    /// 責務: 前の側に同じ時刻の値が複数あれば、最初の値を返すことを確かめます。
    func testDuplicateEarlierSamplesGiveFirstValue() {
        XCTAssertEqual(value(at: 10.5, in: [(10, 1), (10, 2), (12, 3)]), 1)
    }

    /// 責務: 許容差が負か NaN なら、一致する時刻でも `nil` になることを確かめます。
    func testInvalidToleranceGivesNil() {
        XCTAssertNil(value(at: 10, in: [(10, 3)], matcher: RouteAnalysisValueMatcher(toleranceSeconds: -1)))
        XCTAssertNil(value(at: 10, in: [(10, 3)], matcher: RouteAnalysisValueMatcher(toleranceSeconds: .nan)))
    }
}

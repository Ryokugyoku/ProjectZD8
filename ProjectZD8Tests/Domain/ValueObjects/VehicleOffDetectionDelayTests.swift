import XCTest
@testable import ProjectZD8

/// `VehicleOffDetectionDelay` の選択肢・既定値・ナノ秒換算・識別子を検証します。
///
/// 仕様: 選択肢は10・30・60・180秒の4つでこの順に並び、既定は30秒です。
final class VehicleOffDetectionDelayTests: XCTestCase {
    /// 選択肢は4つで、10・30・60・180秒の順に並びます。
    ///
    /// 責務: `CaseIterable` の件数・順序と各値の秒数を確認します。
    func testAllCasesAreFourChoicesInAscendingOrder() {
        XCTAssertEqual(VehicleOffDetectionDelay.allCases.map(\.rawValue), [10, 30, 60, 180])
        XCTAssertEqual(VehicleOffDetectionDelay.seconds10.rawValue, 10)
        XCTAssertEqual(VehicleOffDetectionDelay.seconds30.rawValue, 30)
        XCTAssertEqual(VehicleOffDetectionDelay.seconds60.rawValue, 60)
        XCTAssertEqual(VehicleOffDetectionDelay.seconds180.rawValue, 180)
    }

    /// 既定は30秒です。
    ///
    /// 責務: `default` が30秒の選択肢であることを確認します。
    func testDefaultIsThirtySeconds() {
        XCTAssertEqual(VehicleOffDetectionDelay.default, .seconds30)
        XCTAssertEqual(VehicleOffDetectionDelay.default.rawValue, 30)
    }

    /// ナノ秒は秒数に10億を掛けた値です。
    ///
    /// 責務: 4つの選択肢の `nanoseconds` をリテラルの期待値と照合します。
    func testNanosecondsAreSecondsTimesBillion() {
        XCTAssertEqual(VehicleOffDetectionDelay.seconds10.nanoseconds, 10_000_000_000)
        XCTAssertEqual(VehicleOffDetectionDelay.seconds30.nanoseconds, 30_000_000_000)
        XCTAssertEqual(VehicleOffDetectionDelay.seconds60.nanoseconds, 60_000_000_000)
        XCTAssertEqual(VehicleOffDetectionDelay.seconds180.nanoseconds, 180_000_000_000)
    }

    /// 識別子は秒数で、選択肢ごとに重複しません。
    ///
    /// 責務: `id` が `rawValue` と一致し、全選択肢で一意なことを確認します。
    func testIdentifierIsSecondsAndUnique() {
        XCTAssertEqual(VehicleOffDetectionDelay.allCases.map(\.id), [10, 30, 60, 180])
        XCTAssertEqual(Set(VehicleOffDetectionDelay.allCases.map(\.id)).count, 4)
    }

    /// 選択肢にない秒数からは生成できません。
    ///
    /// 責務: `init(rawValue:)` が選択肢の値だけを受け付けることを確認します。
    func testInitFromRawValueAcceptsOnlyChoices() {
        XCTAssertEqual(VehicleOffDetectionDelay(rawValue: 60), .seconds60)
        XCTAssertNil(VehicleOffDetectionDelay(rawValue: 45))
        XCTAssertNil(VehicleOffDetectionDelay(rawValue: 0))
        XCTAssertNil(VehicleOffDetectionDelay(rawValue: -30))
    }
}

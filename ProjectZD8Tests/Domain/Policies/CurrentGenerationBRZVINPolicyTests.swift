import XCTest
@testable import ProjectZD8

/// 現行世代BRZの保守的なVIN判定を検証します。
final class CurrentGenerationBRZVINPolicyTests: XCTestCase {
    /// 公式資料の17文字BRZ例を受理します。
    ///
    /// 責務: `JF1ZD` の確認済みVINがBRZ Beta対象になることを確認します。
    func testMatchesOfficialBRZVINStructure() {
        XCTAssertTrue(CurrentGenerationBRZVINPolicy().matches("JF1ZDBB1XS9700001"))
    }

    /// 別車種と短い国内型式文字列を拒否します。
    ///
    /// 責務: VINだけで確認できない識別子がBRZ Beta対象にならないことを確認します。
    func testRejectsOtherVehicleAndShortModelCode() {
        let policy = CurrentGenerationBRZVINPolicy()

        XCTAssertFalse(policy.matches("JF1ZNAA1XS9700001"))
        XCTAssertFalse(policy.matches("ZD8"))
        XCTAssertFalse(policy.matches(nil))
    }
}

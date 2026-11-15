import XCTest
@testable import ProjectZD8

/// 記録中表示の車両名欄が、登録名と未登録を分けることを検証します。
final class RecordingSessionActivityVehicleLabelTests: XCTestCase {
    /// 名称があれば名前です。
    ///
    /// 責務: 登録済み車両の名称がそのまま載ることを確認します。
    func testNameIsNamed() {
        XCTAssertEqual(RecordingSessionActivityVehicleLabel(vehicleName: "BRZ"), .named("BRZ"))
    }

    /// 名称なしは未登録です。
    ///
    /// 責務: nil を未登録へ変換することを確認します。
    func testNilIsUnregistered() {
        XCTAssertEqual(RecordingSessionActivityVehicleLabel(vehicleName: nil), .unregistered)
    }

    /// 空文字と空白だけの名称は未登録です。
    ///
    /// 責務: 空・空白・改行だけの境界を未登録へ変換することを確認します。
    func testBlankIsUnregistered() {
        for blank in ["", " ", "  \n\t "] {
            XCTAssertEqual(RecordingSessionActivityVehicleLabel(vehicleName: blank), .unregistered, "\(blank.debugDescription)")
        }
    }

    /// 前後の空白は除いて名前にします。
    ///
    /// 責務: 前後の空白を除き、内部の文字は保つことを確認します。
    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(RecordingSessionActivityVehicleLabel(vehicleName: "  My BRZ \n"), .named("My BRZ"))
    }

    /// 未登録の文言キーは仕様の固定値です。
    ///
    /// 責務: 公開定数の値を確認します。
    func testUnregisteredKey() {
        XCTAssertEqual(RecordingSessionActivityVehicleLabel.unregisteredKey, "live_activity.vehicle.unregistered")
    }
}

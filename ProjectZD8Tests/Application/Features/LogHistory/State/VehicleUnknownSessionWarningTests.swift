import XCTest
@testable import ProjectZD8

/// `VehicleUnknownSessionWarning` の件数からの生成・表示判定・文言キー・埋め込む値・主要操作を、種類と件数の境界で検証します。
///
/// 仕様: U4 受け入れ条件 11・12・15・17(「車両を特定できなかったログが N 件あります」。0件で消える。照会の失敗は空にしない)。
final class VehicleUnknownSessionWarningTests: XCTestCase {
    /// 0件以下は非表示、1件以上は件数つきの警告になります。
    ///
    /// 責務: -1・0 で `.hidden`、1・2・100 で `.sessions(count:)` になることを確認します。
    func testInitFromCount() {
        XCTAssertEqual(VehicleUnknownSessionWarning(count: -1), .hidden)
        XCTAssertEqual(VehicleUnknownSessionWarning(count: 0), .hidden)
        XCTAssertEqual(VehicleUnknownSessionWarning(count: 1), .sessions(count: 1))
        XCTAssertEqual(VehicleUnknownSessionWarning(count: 2), .sessions(count: 2))
        XCTAssertEqual(VehicleUnknownSessionWarning(count: 100), .sessions(count: 100))
    }

    /// 件数ありと照会の失敗は表示し、非表示は表示しません。
    ///
    /// 責務: `isVisible` の3分岐を確認します。
    func testIsVisible() {
        XCTAssertFalse(VehicleUnknownSessionWarning.hidden.isVisible)
        XCTAssertTrue(VehicleUnknownSessionWarning.sessions(count: 1).isVisible)
        XCTAssertTrue(VehicleUnknownSessionWarning.loadFailed.isVisible)
    }

    /// 見出しは件数ありと照会の失敗で別のキーで、非表示では無しです。
    ///
    /// 責務: `titleKey` の3分岐を確認します。
    func testTitleKey() {
        XCTAssertNil(VehicleUnknownSessionWarning.hidden.titleKey)
        XCTAssertEqual(VehicleUnknownSessionWarning.sessions(count: 1).titleKey, "vehicle_unknown.warning.title")
        XCTAssertEqual(VehicleUnknownSessionWarning.sessions(count: 3).titleKey, "vehicle_unknown.warning.title")
        XCTAssertEqual(VehicleUnknownSessionWarning.loadFailed.titleKey, "vehicle_unknown.warning.failure.title")
    }

    /// 本文は1件と2件以上で別のキー、照会の失敗は再読み込みの案内、非表示では無しです。
    ///
    /// 責務: 1件・2件(境界)・多数・失敗・非表示の `messageKey` を確認します。
    func testMessageKey() {
        XCTAssertNil(VehicleUnknownSessionWarning.hidden.messageKey)
        XCTAssertEqual(VehicleUnknownSessionWarning.sessions(count: 1).messageKey, "vehicle_unknown.warning.message.one")
        XCTAssertEqual(VehicleUnknownSessionWarning.sessions(count: 2).messageKey, "vehicle_unknown.warning.message.many")
        XCTAssertEqual(VehicleUnknownSessionWarning.sessions(count: 50).messageKey, "vehicle_unknown.warning.message.many")
        XCTAssertEqual(VehicleUnknownSessionWarning.loadFailed.messageKey, "unassigned_vin.warning.failure.message")
    }

    /// 本文へ埋め込む値は件数ありでは件数だけ、それ以外は空です。
    ///
    /// 責務: `messageArguments` の分岐を確認します。
    func testMessageArguments() {
        XCTAssertEqual(VehicleUnknownSessionWarning.sessions(count: 1).messageArguments, [1])
        XCTAssertEqual(VehicleUnknownSessionWarning.sessions(count: 7).messageArguments, [7])
        XCTAssertEqual(VehicleUnknownSessionWarning.loadFailed.messageArguments, [])
        XCTAssertEqual(VehicleUnknownSessionWarning.hidden.messageArguments, [])
    }

    /// 主要操作は件数ありで一覧を開く操作、照会の失敗で再読み込み、非表示では無しです。
    ///
    /// 責務: `primaryAction` の3分岐を確認します(受け入れ条件 12・15)。
    func testPrimaryAction() {
        XCTAssertNil(VehicleUnknownSessionWarning.hidden.primaryAction)
        XCTAssertEqual(VehicleUnknownSessionWarning.sessions(count: 1).primaryAction, .reviewSessions)
        XCTAssertEqual(VehicleUnknownSessionWarning.loadFailed.primaryAction, .retryLoading)
    }
}

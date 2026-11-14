import Foundation
import XCTest
@testable import ProjectZD8

/// 接続履歴の車両名、取得端末、識別子の文字列表示を検証します。
@MainActor
final class ConnectionHistorySessionTextFormatterTests: XCTestCase {
    /// 検証対象の文字列表示変換です。
    private let formatter = ConnectionHistorySessionTextFormatter()

    /// 車両名がある場合はその名前を返します。
    ///
    /// 責務: 空でない登録車両名をそのまま表示することを確認します。
    func testVehicleNameUsesRegisteredName() {
        let session = ConnectionSession(accountIdentifier: "account", vehicle: makeVehicle(name: "ZD8"))

        XCTAssertEqual(formatter.vehicleName(session), "ZD8")
    }

    /// 車両名が空か車両が無い場合は識別中の文言を返します。
    ///
    /// 責務: 空名と車両無しの両方が `history.vehicle.pending` になることを確認します。
    func testVehicleNameFallsBackToPendingForEmptyOrMissingVehicle() {
        let pending = String(localized: "history.vehicle.pending")
        let emptyName = ConnectionSession(accountIdentifier: "account", vehicle: makeVehicle(name: ""))
        let noVehicle = ConnectionSession(accountIdentifier: "account")

        XCTAssertEqual(formatter.vehicleName(emptyName), pending)
        XCTAssertEqual(formatter.vehicleName(noVehicle), pending)
    }

    /// 車両グループ名は登録車両名、空名やnilは未関連付け文言です。
    ///
    /// 責務: 車両グループ見出しの3分岐を確認します。
    func testVehicleGroupNameUsesNameOrUnassigned() {
        let unassigned = String(localized: "history.vehicle.unassigned")

        XCTAssertEqual(formatter.vehicleGroupName(makeVehicle(name: "ZD8")), "ZD8")
        XCTAssertEqual(formatter.vehicleGroupName(makeVehicle(name: "")), unassigned)
        XCTAssertEqual(formatter.vehicleGroupName(nil), unassigned)
    }

    /// 車両代表識別値は空でない場合だけ返します。
    ///
    /// 責務: 識別値あり、空、車両無しの3分岐を確認します。
    func testVehicleIdentifierReturnsOnlyNonEmptyValue() {
        XCTAssertEqual(formatter.vehicleIdentifier(makeVehicle(displayIdentifier: "JF1ZD8")), "JF1ZD8")
        XCTAssertNil(formatter.vehicleIdentifier(makeVehicle(displayIdentifier: "")))
        XCTAssertNil(formatter.vehicleIdentifier(nil))
    }

    /// セッションIDは先頭8文字の大文字です。
    ///
    /// 責務: UUID文字列の先頭8文字を大文字で返すことを確認します。
    func testShortIDUsesFirstEightUppercasedCharacters() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "abcdef12-3456-7890-abcd-ef1234567890"))

        XCTAssertEqual(formatter.shortID(ConnectionSessionID(rawValue: uuid)), "ABCDEF12")
    }

    /// 取得元端末がある場合は端末名とプラットフォームを返します。
    ///
    /// 責務: 全プラットフォームが `名前 (rawValue)` 形式になることを確認します。
    func testAcquisitionDeviceTextIncludesNameAndPlatform() {
        let cases: [(ConnectionSessionAcquisitionPlatform, String)] = [
            (.iPhone, "Ryo (iPhone)"),
            (.iPad, "Ryo (iPad)"),
            (.macOS, "Ryo (macOS)")
        ]
        for (platform, expected) in cases {
            let device = ConnectionSessionAcquisitionDevice(platform: platform, name: "Ryo")
            let session = ConnectionSession(accountIdentifier: "account", acquisitionDevice: device)

            XCTAssertEqual(formatter.acquisitionDeviceText(session), expected)
        }
    }

    /// 取得元端末が無い旧履歴は不明文言を返します。
    ///
    /// 責務: 取得元端末 `nil` が `history.device.unknown` になることを確認します。
    func testAcquisitionDeviceTextFallsBackToUnknown() {
        let session = ConnectionSession(accountIdentifier: "account")

        XCTAssertEqual(formatter.acquisitionDeviceText(session), String(localized: "history.device.unknown"))
    }

    /// 車両グループ識別子は登録車両UUIDまたは `unassigned` です。
    ///
    /// 責務: 車両グループ識別子の2ケースを確認します。
    func testGroupIdentifierCoversRegisteredAndUnassigned() {
        let vehicleID = VehicleID()

        XCTAssertEqual(formatter.groupIdentifier(.registered(vehicleID)), vehicleID.rawValue.uuidString)
        XCTAssertEqual(formatter.groupIdentifier(.unassigned), "unassigned")
    }

    /// 終了理由キーは終了理由の固定キー、未終了は全件条件のキーです。
    ///
    /// 責務: 全終了理由と `nil` のキー変換を確認します。
    func testEndReasonKeyUsesReasonKeyOrAllFallback() {
        let reasons: [ConnectionSessionEndReason] = [
            .userDisconnected, .vehicleNoResponse, .connectionLost, .acquisitionFailed,
            .superseded, .accountSignedOut, .unexpectedTermination
        ]
        for reason in reasons {
            XCTAssertEqual(formatter.endReasonKey(reason), reason.historyLocalizationKey)
        }
        XCTAssertEqual(formatter.endReasonKey(nil), "history.reason.all")
    }

    /// 検証用の車両表示情報を生成します。
    ///
    /// 責務: 名称と代表識別値だけを変えた車両スナップショットを返します。
    /// - Parameters:
    ///   - name: 車両名称。
    ///   - displayIdentifier: 車両代表識別値。
    /// - Returns: 検証用の車両表示情報。
    private func makeVehicle(name: String = "ZD8", displayIdentifier: String = "JF1ZD8") -> ConnectionSessionVehicle {
        ConnectionSessionVehicle(id: VehicleID(), name: name, displayIdentifier: displayIdentifier)
    }
}

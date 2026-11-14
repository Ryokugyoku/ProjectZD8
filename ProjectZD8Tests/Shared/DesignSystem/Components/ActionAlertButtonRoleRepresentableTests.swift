import SwiftUI
import XCTest
@testable import ProjectZD8

/// 汎用 alert ボタン役割から SwiftUI のボタン役割への変換を検証します。
@MainActor
final class ActionAlertButtonRoleRepresentableTests: XCTestCase {
    /// ケース宣言だけで準拠する検証用の役割です。
    private enum SampleRole: ActionAlertButtonRoleRepresentable {
        case normal
        case cancel
        case destructive
        case emphasized
    }

    /// 取り消し役割は `ButtonRole.cancel` になります。
    ///
    /// 責務: `cancel` 分岐を確認します。
    func testCancelMapsToCancelButtonRole() {
        XCTAssertEqual(SampleRole.cancel.buttonRole, .cancel)
    }

    /// 破壊的役割は `ButtonRole.destructive` になります。
    ///
    /// 責務: `destructive` 分岐を確認します。
    func testDestructiveMapsToDestructiveButtonRole() {
        XCTAssertEqual(SampleRole.destructive.buttonRole, .destructive)
    }

    /// 取り消しでも破壊的でもない役割は役割なしになります。
    ///
    /// 責務: `default` 分岐を、契約外のケースを含めて確認します。
    func testOtherRolesMapToNoButtonRole() {
        XCTAssertNil(SampleRole.normal.buttonRole)
        XCTAssertNil(SampleRole.emphasized.buttonRole)
    }
}

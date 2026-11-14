#if os(macOS)
import SwiftUI
import XCTest
@testable import ProjectZD8

/// 共通の接続履歴 alert 記述が Shared の汎用 alert 契約として読めることを検証します。
@MainActor
final class ConnectionHistoryAlertMacOSPresentationTests: XCTestCase {
    /// macOS の alert 構成です。
    private let factory = ConnectionHistoryAlertFactory()

    /// アップロード失敗 alert は cancel ロールの閉じるボタンと、役割なしの再試行ボタンを並べます。
    ///
    /// 責務: macOS でも iOS と同じボタン順、役割、送出 Action、閉じた時の Action になることを確認します。
    func testUploadFailureAlertOffersRetry() throws {
        let sessionID = ConnectionSessionID()
        var state = ConnectionHistoryState()
        state.uploadFailureSessionID = sessionID
        let alert = try XCTUnwrap(factory.alert(.uploadFailure, in: state))

        XCTAssertEqual(titleKey(of: alert), "history.upload.error.title")
        XCTAssertEqual(dismissAction(of: alert), .sessionUploadFailureDismissed)
        XCTAssertEqual(buttonSummaries(of: alert).map(\.titleKey), ["history.upload.error.dismiss", "history.upload.retry"])
        XCTAssertEqual(buttonSummaries(of: alert).map(\.role), [.cancel, nil])
        XCTAssertEqual(
            buttonSummaries(of: alert).map(\.action),
            [.sessionUploadFailureDismissed, .sessionUploadRequested(sessionID)]
        )
    }

    /// ボタン役割は normal が役割なし、cancel と destructive が同名の SwiftUI 役割になります。
    ///
    /// 責務: 共通ボタン役割の全ケースの準拠経由の変換を確認します。
    func testButtonRolesMapToSwiftUIRoles() {
        XCTAssertNil(ConnectionHistoryAlertButton.Role.normal.buttonRole)
        XCTAssertEqual(ConnectionHistoryAlertButton.Role.cancel.buttonRole, .cancel)
        XCTAssertEqual(ConnectionHistoryAlertButton.Role.destructive.buttonRole, .destructive)
    }

    /// 汎用契約から読む値は共通記述の値そのものです。
    ///
    /// 責務: タイトル、本文、ボタン、閉じる操作が準拠経由で変わらないことを確認します。
    func testGenericContentExposesSameValues() throws {
        var state = ConnectionHistoryState()
        state.sessionDeletionPrompt = ConnectionSessionDeletionPrompt(sessionID: ConnectionSessionID(), recordCount: 4, byteCount: 2_048)
        let alert = try XCTUnwrap(factory.alert(.sessionDeletionConfirmation, in: state))

        XCTAssertEqual(titleKey(of: alert), "history.delete.warning.title")
        XCTAssertEqual(message(of: alert), alert.message)
        XCTAssertEqual(dismissAction(of: alert), .sessionDeletionCancelled)
        XCTAssertEqual(buttonSummaries(of: alert).map(\.titleKey), ["history.delete.cancel", "history.delete.confirm"])
        XCTAssertEqual(buttonSummaries(of: alert).map(\.role), [.cancel, .destructive])
        XCTAssertEqual(buttonSummaries(of: alert).map(\.action), [.sessionDeletionCancelled, .sessionDeletionConfirmed])
    }

    /// macOS で接続する6件の記述列は、表示中の種類だけが値を持ち順序が固定です。
    ///
    /// 責務: View が渡す `allCases` 順の記述列の長さと位置を確認します。
    func testAlertListKeepsKindOrderAndPresentsOnlyActiveKind() {
        var state = ConnectionHistoryState()
        state.stopReviewFailureKey = "history.stop_review.error"
        let alerts = ConnectionHistoryAlertKind.allCases.map { factory.alert($0, in: state) }

        XCTAssertEqual(alerts.count, 6)
        XCTAssertEqual(alerts.map { $0?.kind }, [nil, nil, nil, nil, .stopReviewFailure, nil])
    }

    /// 汎用契約経由でタイトルキーを読みます。
    private func titleKey<Content: ActionAlertContent>(of content: Content) -> String { content.titleKey }
    /// 汎用契約経由で本文を読みます。
    private func message<Content: ActionAlertContent>(of content: Content) -> Content.Message { content.message }
    /// 汎用契約経由で閉じる操作を読みます。
    private func dismissAction<Content: ActionAlertContent>(of content: Content) -> Content.Action { content.dismissAction }
    /// 汎用契約経由でボタンの文言、SwiftUI 役割、操作を読みます。
    private func buttonSummaries<Content: ActionAlertContent>(
        of content: Content
    ) -> [(titleKey: String, role: ButtonRole?, action: Content.Action)] {
        content.buttons.map { ($0.titleKey, $0.role.buttonRole, $0.action) }
    }
}
#endif

import Foundation
import XCTest
@testable import ProjectZD8

/// 接続履歴状態から導出する alert 内容を検証します。
@MainActor
final class ConnectionHistoryAlertFactoryTests: XCTestCase {
    /// iOS と macOS が共有する構成です。
    private let factory = ConnectionHistoryAlertFactory()
    /// 検証用のセッションIDです。
    private let sessionID = ConnectionSessionID()

    /// alert 種類は6種で、View が接続する順に並びます。
    ///
    /// 責務: alert 種類のケース構成と順序を固定します。
    func testAlertKindsCoverSixAlertsInOrder() {
        XCTAssertEqual(
            ConnectionHistoryAlertKind.allCases,
            [.rawRemovalConfirmation, .sessionDeletionConfirmation, .sessionDeletionFailure,
             .stopReviewConfirmation, .stopReviewFailure, .uploadFailure]
        )
    }

    /// 初期状態ではどの alert も表示しません。
    ///
    /// 責務: 全種類で対応 state が `nil` なら `nil` を返すことを確認します。
    func testNoAlertIsPresentedForEmptyState() {
        let state = ConnectionHistoryState()
        for kind in ConnectionHistoryAlertKind.allCases {
            XCTAssertNil(factory.alert(kind, in: state), "\(kind)")
        }
    }

    /// 各 alert は自分の state だけで表示され、他の種類を巻き込みません。
    ///
    /// 責務: 1種類の state だけを設定した時に、その種類だけが表示されることを確認します。
    func testEachAlertIsPresentedOnlyByItsOwnState() {
        for kind in ConnectionHistoryAlertKind.allCases {
            let state = makeState(presenting: kind)
            for other in ConnectionHistoryAlertKind.allCases {
                let alert = factory.alert(other, in: state)
                if other == kind {
                    XCTAssertEqual(alert?.kind, kind)
                } else {
                    XCTAssertNil(alert, "\(kind) が \(other) を表示しないこと")
                }
            }
        }
    }

    /// 安全なRaw除去は safe のタイトルと本文を使います。
    ///
    /// 責務: decision == .safe の場合のタイトル、本文、ボタン、閉じる操作を確認します。
    func testRawRemovalAlertForSafeDecision() {
        var state = ConnectionHistoryState()
        state.rawRemovalPrompt = ConnectionSessionRawRemovalPrompt(sessionID: sessionID, decision: .safe, recordCount: 3, byteCount: 512)

        XCTAssertEqual(
            factory.alert(.rawRemovalConfirmation, in: state),
            ConnectionHistoryAlert(
                kind: .rawRemovalConfirmation,
                titleKey: "history.raw.remove.safe.title",
                message: .rawSummary(formatKey: "history.raw.remove.safe.message", recordCount: 3, byteCount: 512),
                buttons: rawRemovalButtons,
                dismissAction: .localRawRemovalCancelled
            )
        )
    }

    /// safe 以外のRaw除去判断は warning のタイトルと本文を使います。
    ///
    /// 責務: 警告必須と利用不能の両判断が warning になることを確認します。
    func testRawRemovalAlertForNonSafeDecisionsUsesWarning() {
        for decision in [ConnectionSessionLocalRemovalDecision.requiresDataLossWarning, .unavailable] {
            var state = ConnectionHistoryState()
            state.rawRemovalPrompt = ConnectionSessionRawRemovalPrompt(sessionID: sessionID, decision: decision, recordCount: 4, byteCount: -1)

            XCTAssertEqual(
                factory.alert(.rawRemovalConfirmation, in: state),
                ConnectionHistoryAlert(
                    kind: .rawRemovalConfirmation,
                    titleKey: "history.raw.remove.warning.title",
                    message: .rawSummary(formatKey: "history.raw.remove.warning.message", recordCount: 4, byteCount: -1),
                    buttons: rawRemovalButtons,
                    dismissAction: .localRawRemovalCancelled
                ),
                "\(decision)"
            )
        }
    }

    /// セッション削除確認は件数と容量付きの警告と取消・削除ボタンです。
    ///
    /// 責務: 全端末削除確認のタイトル、本文、ボタン順序とロール、閉じる操作を確認します。
    func testSessionDeletionAlert() {
        var state = ConnectionHistoryState()
        state.sessionDeletionPrompt = ConnectionSessionDeletionPrompt(sessionID: sessionID, recordCount: 9, byteCount: 1_000)

        XCTAssertEqual(
            factory.alert(.sessionDeletionConfirmation, in: state),
            ConnectionHistoryAlert(
                kind: .sessionDeletionConfirmation,
                titleKey: "history.delete.warning.title",
                message: .rawSummary(formatKey: "history.delete.warning.message", recordCount: 9, byteCount: 1_000),
                buttons: [
                    ConnectionHistoryAlertButton(titleKey: "history.delete.cancel", role: .cancel, action: .sessionDeletionCancelled),
                    ConnectionHistoryAlertButton(titleKey: "history.delete.confirm", role: .destructive, action: .sessionDeletionConfirmed)
                ],
                dismissAction: .sessionDeletionCancelled
            )
        )
    }

    /// セッション削除失敗は固定文言と通常ロールの閉じるボタンです。
    ///
    /// 責務: 削除失敗 alert の内容を確認します。
    func testSessionDeletionFailureAlert() {
        var state = ConnectionHistoryState()
        state.sessionDeletionFailureKey = "any.failure"

        XCTAssertEqual(
            factory.alert(.sessionDeletionFailure, in: state),
            ConnectionHistoryAlert(
                kind: .sessionDeletionFailure,
                titleKey: "history.delete.error.title",
                message: .localized(key: "history.delete.error"),
                buttons: [
                    ConnectionHistoryAlertButton(titleKey: "history.delete.error.dismiss", role: .normal, action: .sessionDeletionFailureDismissed)
                ],
                dismissAction: .sessionDeletionFailureDismissed
            )
        )
    }

    /// 車両無応答の停止確認は no_response の本文を使います。
    ///
    /// 責務: vehicleNoResponse の停止確認 alert 内容を確認します。
    func testStopReviewAlertForVehicleNoResponse() {
        var state = ConnectionHistoryState()
        state.stopReviewPrompt = ConnectionSessionStopReviewPrompt(sessionID: sessionID, observedReason: .vehicleNoResponse)

        XCTAssertEqual(
            factory.alert(.stopReviewConfirmation, in: state),
            ConnectionHistoryAlert(
                kind: .stopReviewConfirmation,
                titleKey: "history.stop_review.title",
                message: .localized(key: "history.stop_review.message.no_response"),
                buttons: stopReviewButtons,
                dismissAction: .stopReviewCancelled
            )
        )
    }

    /// 車両無応答以外の停止確認は connection_lost の本文を使います。
    ///
    /// 責務: vehicleNoResponse 以外の全終了理由で connection_lost になることを確認します。
    func testStopReviewAlertForOtherReasonsUsesConnectionLostMessage() {
        let reasons: [ConnectionSessionEndReason] = [
            .userDisconnected, .connectionLost, .acquisitionFailed, .superseded, .accountSignedOut, .unexpectedTermination
        ]
        for reason in reasons {
            var state = ConnectionHistoryState()
            state.stopReviewPrompt = ConnectionSessionStopReviewPrompt(sessionID: sessionID, observedReason: reason)
            let alert = factory.alert(.stopReviewConfirmation, in: state)

            XCTAssertEqual(alert?.message, .localized(key: "history.stop_review.message.connection_lost"), "\(reason)")
            XCTAssertEqual(alert?.buttons, stopReviewButtons)
        }
    }

    /// 停止確認保存失敗は固定文言と通常ロールの閉じるボタンです。
    ///
    /// 責務: 停止確認失敗 alert の内容を確認します。
    func testStopReviewFailureAlert() {
        var state = ConnectionHistoryState()
        state.stopReviewFailureKey = "any.failure"

        XCTAssertEqual(
            factory.alert(.stopReviewFailure, in: state),
            ConnectionHistoryAlert(
                kind: .stopReviewFailure,
                titleKey: "history.stop_review.error.title",
                message: .localized(key: "history.stop_review.error"),
                buttons: [
                    ConnectionHistoryAlertButton(titleKey: "history.stop_review.error.dismiss", role: .normal, action: .stopReviewFailureDismissed)
                ],
                dismissAction: .stopReviewFailureDismissed
            )
        )
    }

    /// アップロード失敗は両 OS 共通で、取消ロールの閉じると再試行を並べます。
    ///
    /// 責務: アップロード失敗 alert が失敗セッションの再アップロードを送ることを確認します。
    func testUploadFailureAlertOffersRetry() {
        var state = ConnectionHistoryState()
        state.uploadFailureSessionID = sessionID

        XCTAssertEqual(
            factory.alert(.uploadFailure, in: state),
            ConnectionHistoryAlert(
                kind: .uploadFailure,
                titleKey: "history.upload.error.title",
                message: .localized(key: "history.upload.error.message"),
                buttons: [
                    ConnectionHistoryAlertButton(titleKey: "history.upload.error.dismiss", role: .cancel, action: .sessionUploadFailureDismissed),
                    ConnectionHistoryAlertButton(titleKey: "history.upload.retry", role: .normal, action: .sessionUploadRequested(sessionID))
                ],
                dismissAction: .sessionUploadFailureDismissed
            )
        )
    }

    /// ボタンの役割は通常、取消、破壊的の3種です。
    ///
    /// 責務: ボタン役割 enum のケース構成を固定し、生成値の保持を確認します。
    func testAlertButtonRolesAndValues() {
        let button = ConnectionHistoryAlertButton(titleKey: "k", role: .destructive, action: .filtersReset)

        XCTAssertEqual(ConnectionHistoryAlertButton.Role.allCases, [.normal, .cancel, .destructive])
        XCTAssertEqual(button.titleKey, "k")
        XCTAssertEqual(button.role, .destructive)
        XCTAssertEqual(button.action, .filtersReset)
    }

    /// Raw除去確認の取消・除去ボタンです。
    private var rawRemovalButtons: [ConnectionHistoryAlertButton] {
        [
            ConnectionHistoryAlertButton(titleKey: "history.raw.remove.cancel", role: .cancel, action: .localRawRemovalCancelled),
            ConnectionHistoryAlertButton(titleKey: "history.raw.remove.confirm", role: .destructive, action: .localRawRemovalConfirmed)
        ]
    }

    /// 停止確認の取消・確定ボタンです。
    private var stopReviewButtons: [ConnectionHistoryAlertButton] {
        [
            ConnectionHistoryAlertButton(titleKey: "history.stop_review.cancel", role: .cancel, action: .stopReviewCancelled),
            ConnectionHistoryAlertButton(titleKey: "history.stop_review.confirm", role: .normal, action: .stopReviewConfirmed)
        ]
    }

    /// 指定種類の alert だけを表示させる履歴状態を生成します。
    ///
    /// 責務: 1種類の alert 表示条件だけを満たす state を返します。
    /// - Parameter kind: 表示させる alert の種類。
    /// - Returns: 対応する state だけを設定した履歴状態。
    private func makeState(presenting kind: ConnectionHistoryAlertKind) -> ConnectionHistoryState {
        var state = ConnectionHistoryState()
        switch kind {
        case .rawRemovalConfirmation:
            state.rawRemovalPrompt = ConnectionSessionRawRemovalPrompt(sessionID: sessionID, decision: .safe, recordCount: 1, byteCount: 1)
        case .sessionDeletionConfirmation:
            state.sessionDeletionPrompt = ConnectionSessionDeletionPrompt(sessionID: sessionID, recordCount: 1, byteCount: 1)
        case .sessionDeletionFailure:
            state.sessionDeletionFailureKey = "failure"
        case .stopReviewConfirmation:
            state.stopReviewPrompt = ConnectionSessionStopReviewPrompt(sessionID: sessionID, observedReason: .connectionLost)
        case .stopReviewFailure:
            state.stopReviewFailureKey = "failure"
        case .uploadFailure:
            state.uploadFailureSessionID = sessionID
        }
        return state
    }
}

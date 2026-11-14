/// 接続履歴状態から各 alert の表示内容を導出します。
///
/// 表示条件は従来の View の `isPresented` と同じで、対応する state が `nil` の場合は alert を返しません。
struct ConnectionHistoryAlertFactory {
    /// 指定種類の alert を現在の履歴状態から返します。
    ///
    /// 責務: 1種類の alert について表示条件を判定し、表示する場合はその内容へ変換します。
    /// - Parameters:
    ///   - kind: 導出する alert の種類。
    ///   - state: 現在の接続履歴状態。
    /// - Returns: 表示すべき alert。表示しない場合は `nil`。
    func alert(_ kind: ConnectionHistoryAlertKind, in state: ConnectionHistoryState) -> ConnectionHistoryAlert? {
        switch kind {
        case .rawRemovalConfirmation: state.rawRemovalPrompt.map(rawRemovalAlert)
        case .sessionDeletionConfirmation: state.sessionDeletionPrompt.map(sessionDeletionAlert)
        case .sessionDeletionFailure: state.sessionDeletionFailureKey.map { _ in sessionDeletionFailureAlert() }
        case .stopReviewConfirmation: state.stopReviewPrompt.map(stopReviewAlert)
        case .stopReviewFailure: state.stopReviewFailureKey.map { _ in stopReviewFailureAlert() }
        case .uploadFailure: state.uploadFailureSessionID.map(uploadFailureAlert)
        }
    }

    /// ローカルRawログ容量解放の確認 alert を返します。
    ///
    /// 責務: 1件の除去確認内容を安全判断に応じたタイトルと件数・容量付き本文へ変換します。
    /// - Parameter prompt: Applicationが準備したローカル除去確認内容。
    /// - Returns: 取消と除去確定のボタンを持つ alert。
    private func rawRemovalAlert(_ prompt: ConnectionSessionRawRemovalPrompt) -> ConnectionHistoryAlert {
        let isSafe = prompt.decision == .safe
        return ConnectionHistoryAlert(
            kind: .rawRemovalConfirmation,
            titleKey: isSafe ? "history.raw.remove.safe.title" : "history.raw.remove.warning.title",
            message: .rawSummary(
                formatKey: isSafe ? "history.raw.remove.safe.message" : "history.raw.remove.warning.message",
                recordCount: prompt.recordCount,
                byteCount: prompt.byteCount
            ),
            buttons: [
                ConnectionHistoryAlertButton(titleKey: "history.raw.remove.cancel", role: .cancel, action: .localRawRemovalCancelled),
                ConnectionHistoryAlertButton(titleKey: "history.raw.remove.confirm", role: .destructive, action: .localRawRemovalConfirmed)
            ],
            dismissAction: .localRawRemovalCancelled
        )
    }

    /// 全端末セッション削除の確認 alert を返します。
    ///
    /// 責務: 1件の削除確認内容を不可逆性と件数・容量を含む警告へ変換します。
    /// - Parameter prompt: Applicationが準備した全端末削除確認内容。
    /// - Returns: 取消と削除確定のボタンを持つ alert。
    private func sessionDeletionAlert(_ prompt: ConnectionSessionDeletionPrompt) -> ConnectionHistoryAlert {
        ConnectionHistoryAlert(
            kind: .sessionDeletionConfirmation,
            titleKey: "history.delete.warning.title",
            message: .rawSummary(
                formatKey: "history.delete.warning.message",
                recordCount: prompt.recordCount,
                byteCount: prompt.byteCount
            ),
            buttons: [
                ConnectionHistoryAlertButton(titleKey: "history.delete.cancel", role: .cancel, action: .sessionDeletionCancelled),
                ConnectionHistoryAlertButton(titleKey: "history.delete.confirm", role: .destructive, action: .sessionDeletionConfirmed)
            ],
            dismissAction: .sessionDeletionCancelled
        )
    }

    /// 全端末セッション削除の失敗 alert を返します。
    ///
    /// 責務: 削除失敗の通知を固定文言と閉じるボタンへ変換します。
    /// - Returns: 閉じるボタンだけを持つ alert。
    private func sessionDeletionFailureAlert() -> ConnectionHistoryAlert {
        ConnectionHistoryAlert(
            kind: .sessionDeletionFailure,
            titleKey: "history.delete.error.title",
            message: .localized(key: "history.delete.error"),
            buttons: [
                ConnectionHistoryAlertButton(titleKey: "history.delete.error.dismiss", role: .normal, action: .sessionDeletionFailureDismissed)
            ],
            dismissAction: .sessionDeletionFailureDismissed
        )
    }

    /// ユーザー操作による停止かの確認 alert を返します。
    ///
    /// 責務: 1件の停止確認内容を観測済み終了理由に応じた断定を避けた確認文へ変換します。
    /// - Parameter prompt: Applicationが準備した停止確認内容。
    /// - Returns: 取消と停止確定のボタンを持つ alert。
    private func stopReviewAlert(_ prompt: ConnectionSessionStopReviewPrompt) -> ConnectionHistoryAlert {
        ConnectionHistoryAlert(
            kind: .stopReviewConfirmation,
            titleKey: "history.stop_review.title",
            message: .localized(key: prompt.observedReason == .vehicleNoResponse
                ? "history.stop_review.message.no_response"
                : "history.stop_review.message.connection_lost"),
            buttons: [
                ConnectionHistoryAlertButton(titleKey: "history.stop_review.cancel", role: .cancel, action: .stopReviewCancelled),
                ConnectionHistoryAlertButton(titleKey: "history.stop_review.confirm", role: .normal, action: .stopReviewConfirmed)
            ],
            dismissAction: .stopReviewCancelled
        )
    }

    /// 停止確認保存の失敗 alert を返します。
    ///
    /// 責務: 停止確認保存失敗の通知を固定文言と閉じるボタンへ変換します。
    /// - Returns: 閉じるボタンだけを持つ alert。
    private func stopReviewFailureAlert() -> ConnectionHistoryAlert {
        ConnectionHistoryAlert(
            kind: .stopReviewFailure,
            titleKey: "history.stop_review.error.title",
            message: .localized(key: "history.stop_review.error"),
            buttons: [
                ConnectionHistoryAlertButton(titleKey: "history.stop_review.error.dismiss", role: .normal, action: .stopReviewFailureDismissed)
            ],
            dismissAction: .stopReviewFailureDismissed
        )
    }

    /// iCloud個別アップロードの失敗 alert を返します。
    ///
    /// 責務: 1件のアップロード失敗セッションを閉じる操作と再試行操作へ変換します。
    /// - Parameter sessionID: アップロードに失敗したセッションID。
    /// - Returns: 取消役割の閉じると再試行を持つ alert。
    private func uploadFailureAlert(_ sessionID: ConnectionSessionID) -> ConnectionHistoryAlert {
        return ConnectionHistoryAlert(
            kind: .uploadFailure,
            titleKey: "history.upload.error.title",
            message: .localized(key: "history.upload.error.message"),
            buttons: [
                ConnectionHistoryAlertButton(titleKey: "history.upload.error.dismiss", role: .cancel, action: .sessionUploadFailureDismissed),
                ConnectionHistoryAlertButton(titleKey: "history.upload.retry", role: .normal, action: .sessionUploadRequested(sessionID))
            ],
            dismissAction: .sessionUploadFailureDismissed
        )
    }
}

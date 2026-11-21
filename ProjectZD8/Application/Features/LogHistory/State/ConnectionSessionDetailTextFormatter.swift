import Foundation

/// 接続セッション詳細画面の判定、文字列整形、ローカライズキーの選択を返します。
///
/// iOS と macOS の詳細画面で共通に使う純粋な表示変換です。ローカライズキーは `String` で返し、View 側で `LocalizedStringKey` に包みます。
struct ConnectionSessionDetailTextFormatter {
    /// 詳細画面の取得元端末表示を返します。
    ///
    /// 責務: 1件のセッションの取得元端末を、履歴一覧と同じ規則でプラットフォーム付き表示名へ変換します。
    /// - Parameter session: 取得元端末を表示するセッション。
    /// - Returns: `端末名 (プラットフォーム)`、または `history.device.unknown` の文言。
    func acquisitionDeviceText(_ session: ConnectionSession) -> String {
        ConnectionHistorySessionTextFormatter().acquisitionDeviceText(session)
    }

    /// 停止確認カードの本文に使うローカライズキーを返します。
    ///
    /// 責務: 1件のセッションの観測済み終了理由を、車両無応答か接続断の本文キーへ変換します。
    /// - Parameter session: 停止確認を表示するセッション。
    /// - Returns: `history.stop_review.card.no_response` または `history.stop_review.card.connection_lost`。
    func stopReviewMessageKey(_ session: ConnectionSession) -> String {
        session.endReason == .vehicleNoResponse
            ? "history.stop_review.card.no_response"
            : "history.stop_review.card.connection_lost"
    }

    /// バイト数を現在 Locale 向けのファイル容量表現へ変換します。
    ///
    /// 責務: 1件のバイト数を、負の値を0として扱ったファイル容量文字列へ変換します。
    /// - Parameter bytes: Raw Payload の合計バイト数。
    /// - Returns: 現在 Locale へ整形した容量文字列。
    func byteCountText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    /// セッションの正式データ判定を短い表示値へ変換します。
    ///
    /// 責務: 1件のセッションの接続状態・停止確認・終了状態から、判定の文言を1つ選びます。
    /// - Parameter session: 判定を表示するセッション。
    /// - Returns: 接続中、要確認、ユーザー承認済み、正式、中断のいずれかの文言。
    func dispositionText(_ session: ConnectionSession) -> String {
        if session.status == .connected { return String(localized: "history.status.connected") }
        if session.needsStopReview { return String(localized: "history.detail.disposition.review") }
        if session.stopReviewDecision == .userInitiated {
            return String(localized: "history.detail.disposition.user_accepted")
        }
        return session.status == .completed
            ? String(localized: "history.detail.disposition.regular")
            : String(localized: "history.status.interrupted")
    }

    /// アプリが観測した終了理由の表示文字列を返します。
    ///
    /// 責務: 1件のセッションの任意終了理由を、文言または未観測を示す `—` へ変換します。
    /// - Parameter session: 終了理由を表示するセッション。
    /// - Returns: 終了理由の文言。終了理由が無い場合は `—`。
    func observedEndReasonText(_ session: ConnectionSession) -> String {
        guard let reason = session.endReason else { return "—" }
        return String(localized: String.LocalizationValue(reason.historyLocalizationKey))
    }

    /// 履歴表示用の現在状態に対応するローカライズキーを返します。
    ///
    /// 責務: 1件のセッションの状態を、接続中・完了・中断のローカライズキーへ変換します。
    /// - Parameter session: 状態を表示するセッション。
    /// - Returns: View 側で `LocalizedStringKey` に包むローカライズキー。
    func sessionStatusKey(_ session: ConnectionSession) -> String {
        switch session.status {
        case .connected: "history.status.connected"
        case .completed: "history.status.completed"
        case .interrupted: "history.status.interrupted"
        }
    }

    /// セッションを車両別の学習抽出へ使用できるかを返します。
    ///
    /// 責務: 車両の確定、ローカル Raw の保持、記録件数、Mac への取り込み完了がすべて揃っているかを判定します。
    /// - Parameter session: 判定するセッション。
    /// - Returns: すべての条件を満たす場合は `true`。
    func isTrainingReady(_ session: ConnectionSession) -> Bool {
        session.vehicle != nil
            && session.rawLogSummary.localState == .available
            && session.rawLogSummary.recordCount > 0
            && session.rawLogSummary.isDurablyImportedByMac
    }

    /// 解析カードの補足に使う、解析対象の Raw ログ件数の文字列を返します。
    ///
    /// 責務: 1件のセッションの Raw 記録件数を、現在 Locale で整形した補足文へ変換します。
    /// - Parameter session: 解析対象のセッション。
    /// - Returns: `analysis.card.caption` に件数を埋め込んだ文字列。
    func analysisCardCaption(_ session: ConnectionSession) -> String {
        String(
            format: String(localized: "analysis.card.caption"),
            locale: .autoupdatingCurrent,
            session.rawLogSummary.recordCount
        )
    }
}

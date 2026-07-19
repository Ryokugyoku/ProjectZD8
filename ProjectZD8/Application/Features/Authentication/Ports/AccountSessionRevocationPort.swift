/// アカウント別セッション失効の端末間同期を抽象化します。
@MainActor
protocol AccountSessionRevocationPort: AnyObject {
    /// 新規ログイン時点の失効世代を現在セッションの基準として保存します。
    ///
    /// 責務: 新規認証セッションが受理した失効世代を端末内基準へ記録します。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てたユーザー識別子。
    func registerCurrentSession(for userIdentifier: String)

    /// 現在アカウントの新しい失効世代を端末間同期へ発行します。
    ///
    /// 責務: 1件のアカウント削除を他端末が検出可能な新規失効世代へ変換します。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てたユーザー識別子。
    func publishRevocation(for userIdentifier: String)

    /// 指定アカウントについて現在基準より新しい失効世代を監視します。
    ///
    /// 責務: 1件のアカウントに届いた未受理の失効世代だけをコールバックへ通知します。
    /// - Parameters:
    ///   - userIdentifier: Appleがこのアプリへ割り当てたユーザー識別子。
    ///   - receive: 他端末の失効を検出したときに実行する処理。
    func startObserving(
        for userIdentifier: String,
        receive: @escaping () -> Void
    )

    /// 現在のセッション失効監視を終了します。
    ///
    /// 責務: 登録済みの失効通知購読とコールバックを破棄します。
    func stopObserving()
}

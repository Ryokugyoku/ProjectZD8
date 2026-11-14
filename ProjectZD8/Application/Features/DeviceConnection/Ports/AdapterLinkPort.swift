import Foundation

/// 登録済みアダプターへ保留中の接続要求を出し続け、送受信を提供する常駐リンクの能力です。
@MainActor
protocol AdapterLinkPort: AnyObject {
    /// 現在のリンク状態です。
    var state: AdapterLinkState { get }

    /// リンク状態が変化したときに新しい状態を受け取る処理です。
    var stateDidChange: (@MainActor (AdapterLinkState) -> Void)? { get set }

    /// アダプターから受信したバイトを届いた順にそのまま受け取る処理です。
    var dataDidReceive: (@MainActor (Data) -> Void)? { get set }

    /// 指定された登録済みアダプターへのリンクを開始します。
    ///
    /// 責務: 1件の登録済みアダプター識別情報を常駐リンクの接続対象へ固定して接続手順を始めます。
    /// - Parameter preference: 接続対象の登録済みアダプター設定。
    /// - Side Effects: Bluetoothの取得・スキャン・接続要求を開始します。
    func start(preference: DefaultAdapterPreference)

    /// 現在のリンクを停止して `idle` へ戻します。
    ///
    /// 責務: スキャン・接続要求・待機・書き込み待ちを破棄してリンクを未開始状態へ戻します。
    /// - Side Effects: 接続をキャンセルし、待機中の `write(_:)` を `AdapterLinkWriteError.stopped` で終了させます。
    func stop()

    /// アダプターへバイト列を送信します。
    ///
    /// 責務: 1件のバイト列を呼び出し順を保ってアダプターへ書き込みます。
    /// - Parameter data: 送信するバイト列。
    /// - Throws: `ready` でない場合や完了前に切断・停止した場合の `AdapterLinkWriteError`。
    func write(_ data: Data) async throws
}

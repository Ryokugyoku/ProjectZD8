import Foundation

/// ELM/STN系アダプターとのバイトストリーム通信能力です。
protocol OBDCommandTransport: Sendable {
    /// 物理終端を開きます。
    ///
    /// 責務: 1件のOBDアダプター物理終端を読書き可能状態へ遷移させます。
    /// - Throws: 終端を開けない場合は型付き識別エラー。
    func open() async throws

    /// 1件の復帰文字終端コマンドを書き込みます。
    ///
    /// 責務: 1件の完全なホスト対アダプターコマンドをバイトストリームへ送ります。
    /// - Parameter data: 復帰文字を含む完全なASCIIコマンド。
    /// - Throws: 全バイトを書き込めない場合の通信エラー。
    func write(_ data: Data) async throws

    /// ELM/STNプロンプトまでの応答を読み取ります。
    ///
    /// 責務: 現在要求の応答を次の `>` プロンプトまで境界を保って返します。
    /// - Returns: プロンプトを含む加工前応答バイト。
    /// - Throws: 期限切れ、切断、読取失敗の場合の通信エラー。
    func readUntilPrompt() async throws -> Data

    /// 物理終端を閉じます。
    ///
    /// 責務: 現在のアダプターバイトストリームを再利用せず終了します。
    func close() async
}

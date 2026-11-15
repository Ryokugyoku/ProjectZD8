import Foundation

/// 常駐リンクの占有権を持っている間だけ、監視用のELM/STNコマンドを1件ずつ実行する手続きです。
///
/// コマンドごとにホスト側の待機上限を変えられ、プロンプトの無い受信監視(`ATMA`)も扱えるため、
/// 待機上限が固定の `SerializedELMCommandChannel` ではなくこの型を監視用に使います。
/// 直列化は占有権(同時に1利用者)と、各メソッドが応答まで待ってから返ることで保証します。
@MainActor
struct AdapterLinkELMCommandSession {
    /// 送受信を占有しているバイトストリームです。
    private let stream: AdapterLinkByteStream
    /// 取得済みの占有権です。
    private let lease: AdapterLinkByteStreamLease

    /// 占有権を取得して手続きを実行し、終了時に必ず解放します。
    ///
    /// 責務: 1回分の監視操作を占有権の取得から解放までの区間に閉じ込めます。リンクは止めません。
    /// - Parameters:
    ///   - stream: 常駐リンクの受信を引き受けるバイトストリーム。
    ///   - body: 占有中に実行する手続き。
    /// - Returns: 手続きの結果。
    /// - Throws: 占有権を得られない場合の `AdapterLinkByteStreamError`、または手続きが投げたエラー。
    static func perform<Value>(
        on stream: AdapterLinkByteStream,
        _ body: (AdapterLinkELMCommandSession) async throws -> Value
    ) async throws -> Value {
        let lease = try await stream.acquireLease()
        defer { stream.release(lease) }
        return try await body(AdapterLinkELMCommandSession(stream: stream, lease: lease))
    }

    /// 占有権を固定して生成します。
    ///
    /// 責務: 1件の占有権を持つ手続きを用意します。
    /// - Parameters:
    ///   - stream: 送受信を占有しているバイトストリーム。
    ///   - lease: 取得済みの占有権。
    private init(stream: AdapterLinkByteStream, lease: AdapterLinkByteStreamLease) {
        self.stream = stream
        self.lease = lease
    }

    /// コマンドを送ってプロンプトまでの応答を返します。
    ///
    /// 責務: 1件のコマンドを書き込み、指定上限でプロンプトまでの応答を文字列で返します。
    /// - Parameters:
    ///   - command: 送るコマンド。
    ///   - timeout: プロンプトを待つ上限。
    /// - Returns: `>` を除いた加工前応答。
    /// - Throws: 送受信の `AdapterLinkByteStreamError`、文字列化できない場合の `.malformedResponse`。
    ///   キャンセル済みなら送信せず `CancellationError`(取り消された確認が次のコマンドを送らず占有権をすぐ手放すため)。
    func execute(_ command: some ELM327CommandEncoding, timeout: Duration) async throws -> String {
        try Task.checkCancellation()
        try await stream.write(command.encodedData, lease: lease)
        let data = try await stream.readUntilPrompt(lease: lease, timeout: timeout)
        return try Self.text(from: data, requestID: command.requestID)
    }

    /// コマンドを送り、`?` で拒否されていないことを確かめて応答を返します。
    ///
    /// 責務: 設定コマンドが受け付けられたことを確認し、拒否を成功として扱いません。
    /// - Parameters:
    ///   - command: 送るコマンド。
    ///   - timeout: プロンプトを待つ上限。
    /// - Returns: `>` を除いた加工前応答。
    /// - Throws: 拒否は `AdapterLinkELMCommandError.commandRejected`、ほか `execute` と同じ。
    func executeAccepted(_ command: some ELM327CommandEncoding, timeout: Duration) async throws -> String {
        let response = try await execute(command, timeout: timeout)
        guard !ELM327ResponseLines.isRejection(response) else {
            throw AdapterLinkELMCommandError.commandRejected(requestID: command.requestID)
        }
        return response
    }

    /// 受信監視コマンドを送り、時間窓の受信を集めてから監視を止めます。
    ///
    /// 責務: 監視を始め、窓の間の受信を集め、プロンプトが来ていなければ止める文字を送ってプロンプトまで読み、
    /// アダプターをコマンド待ちへ戻してから全受信を返します。
    /// - Parameters:
    ///   - command: 受信監視コマンド。
    ///   - window: 受信を集める時間。
    ///   - stopTimeout: 止める文字を送った後にプロンプトを待つ上限。
    /// - Returns: 監視開始から停止までの `>` を除いた全受信。
    /// - Throws: 送受信の `AdapterLinkByteStreamError`(停止後のプロンプト期限切れを含む)、文字列化できない場合の `.malformedResponse`。
    func monitor(_ command: some ELM327CommandEncoding, window: Duration, stopTimeout: Duration) async throws -> String {
        try Task.checkCancellation()
        try await stream.write(command.encodedData, lease: lease)
        let collected = try await stream.collect(lease: lease, window: window)
        var received = collected.data
        if !collected.endedWithPrompt {
            try await stream.write(ELM327MonitorInterruptCommand().encodedData, lease: lease)
            received.append(try await stream.readUntilPrompt(lease: lease, timeout: stopTimeout))
        }
        return try Self.text(from: received, requestID: command.requestID)
    }

    /// 受信バイトを文字列へ変換します。
    ///
    /// 責務: UTF-8として解釈し、プロンプト `>` を取り除きます。
    /// - Parameters:
    ///   - data: 受信バイト。
    ///   - requestID: 失敗時に保持する要求識別子。
    /// - Returns: `>` を除いた文字列。
    /// - Throws: UTF-8として解釈できない場合の `AdapterLinkELMCommandError.malformedResponse`。
    private static func text(from data: Data, requestID: String) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw AdapterLinkELMCommandError.malformedResponse(requestID: requestID)
        }
        return text.replacingOccurrences(of: ">", with: "")
    }
}

import Foundation
@testable import ProjectZD8

/// 書き込みを記録し、コマンドごとの台本どおりに受信バイトを返す常駐リンクの fake です。
///
/// ELM/STN の受信監視(`ATMA`)も模します。監視中に何らかのバイトを受け取ると監視を止め、
/// そのバイトはコマンドとして処理せずに停止応答だけを返します(実機の ELM327 と同じ振る舞い)。
@MainActor
final class ScriptedAdapterLinkFake: AdapterLinkPort {
    /// 現在のリンク状態です。テストが直接変更します。
    var state: AdapterLinkState

    /// リンク状態の変化を受け取る処理です(この fake からは呼びません)。
    var stateDidChange: (@MainActor (AdapterLinkState) -> Void)?

    /// 受信バイトを受け取る処理です。テスト対象のバイトストリームが設定します。
    var dataDidReceive: (@MainActor (Data) -> Void)?

    /// コマンド(復帰文字を除き大文字化)ごとの応答テキストです。無いコマンドには何も返しません。
    var replies: [String: String] = [:]

    /// 受信監視を始めるコマンドです。
    var monitorStartCommand = "ATMA"

    /// 受信監視中に流す受信テキスト(プロンプトなし)です。`nil` なら監視を始めず `replies` に従います。
    var monitorOutput: String?

    /// 監視を止めたときに返す応答です。`nil` なら何も返しません。
    var monitorStopReply: String? = "STOPPED\r\r>"

    /// 書き込まれた時点でリンクを切断状態にするコマンドです。
    var disconnectingCommands: Set<String> = []

    /// `start(preference:)` が呼ばれた回数です。
    private(set) var startCount = 0

    /// `stop()` が呼ばれた回数です。
    private(set) var stopCount = 0

    /// 書き込まれたバイト列です(呼び出し順)。
    private(set) var writes: [Data] = []

    /// 受信監視中かどうかです。
    private(set) var isMonitoring = false

    /// 受信監視中に書き込まれたため、監視の停止にだけ使われてコマンドとして実行されなかったコマンドです。
    ///
    /// 停止用の空コマンド(復帰文字だけ)は含めません。
    private(set) var commandsSwallowedByMonitor: [String] = []

    /// 初期状態を指定して生成します。
    ///
    /// 責務: 台本の空な fake を指定のリンク状態で用意します。
    /// - Parameter state: 初期のリンク状態。
    init(state: AdapterLinkState = .ready) {
        self.state = state
    }

    /// 書き込まれたコマンドを復帰文字を除いて大文字化した列です。
    var writtenCommands: [String] {
        writes.map(Self.command(from:))
    }

    /// 開始を記録します。
    ///
    /// 責務: テスト対象がリンクを開始していないことを検証するために回数だけ数えます。
    /// - Parameter preference: 接続対象の設定。
    func start(preference: DefaultAdapterPreference) {
        startCount += 1
    }

    /// 停止を記録します。
    ///
    /// 責務: テスト対象がリンクを止めていないことを検証するために回数だけ数えます。
    func stop() {
        stopCount += 1
    }

    /// 書き込みを記録し、台本どおりに受信を返します。
    ///
    /// 責務: `ready` でなければ失敗し、そうでなければバイト列を記録して監視停止・切断・応答のいずれかを模します。
    /// - Parameter data: 書き込まれたバイト列。
    /// - Throws: `ready` でない場合の `AdapterLinkWriteError.notReady`。
    func write(_ data: Data) async throws {
        guard state == .ready else { throw AdapterLinkWriteError.notReady }
        writes.append(data)
        respond(to: Self.command(from: data))
    }

    /// テストから受信テキストを流します。
    ///
    /// 責務: 指定テキストを UTF-8 のまま受信先へ渡します。
    /// - Parameter text: 届いたことにする受信テキスト。
    func deliver(_ text: String) {
        dataDidReceive?(Data(text.utf8))
    }

    /// 1件のコマンドへの台本どおりの反応を起こします。
    ///
    /// 責務: 監視中なら停止、切断対象なら切断、監視開始なら監視出力、それ以外は台本の応答を返します。
    /// - Parameter command: 正規化済みのコマンド。
    private func respond(to command: String) {
        if isMonitoring {
            isMonitoring = false
            if !command.isEmpty { commandsSwallowedByMonitor.append(command) }
            if let monitorStopReply { deliver(monitorStopReply) }
            return
        }
        if disconnectingCommands.contains(command) {
            state = .disconnected(.peripheralDisconnected(errorDescription: nil))
            return
        }
        if command == monitorStartCommand, let monitorOutput {
            isMonitoring = true
            deliver(monitorOutput)
            return
        }
        if let reply = replies[command] { deliver(reply) }
    }

    /// 書き込みバイトをコマンド文字列へ正規化します。
    ///
    /// 責務: 復帰文字と改行を取り除いて大文字化します。
    /// - Parameter data: 書き込まれたバイト列。
    /// - Returns: 正規化したコマンド。
    private static func command(from data: Data) -> String {
        String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
            .uppercased()
    }
}

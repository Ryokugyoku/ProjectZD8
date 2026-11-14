import Foundation
@testable import ProjectZD8

/// 送信されたコマンドを記録し、予約した応答を順に返すコマンドTransportのフェイクです。
///
/// 応答が尽きたら応答期限切れを送出します。実時間では待ちません。
@MainActor
final class ScriptedOBDCommandTransportFake: OBDCommandTransport {
    /// 未使用の応答です。
    private var responses: [String]
    /// 送信されたコマンドです。送信順に並びます。
    private(set) var commands: [String] = []
    /// `open` が呼ばれた回数です。
    private(set) var openCount = 0
    /// `close` が呼ばれた回数です。
    private(set) var closeCount = 0

    /// 応答を予約して生成します。
    ///
    /// 責務: 読み取りごとに先頭から返す応答を保持します。
    /// - Parameter responses: 返す応答。
    init(responses: [String]) {
        self.responses = responses
    }

    /// 応答を予約の末尾へ追加します。
    ///
    /// 責務: 後から読まれる応答を追加します。
    /// - Parameter more: 追加する応答。
    func append(_ more: [String]) {
        responses += more
    }

    /// `open` を記録します。
    ///
    /// 責務: 開いた回数を数えます。
    func open() async throws {
        openCount += 1
    }

    /// 送信されたコマンドを記録します。
    ///
    /// 責務: 送信データをUTF-8の文字列として記録します。
    /// - Parameter data: 送信データ。
    func write(_ data: Data) async throws {
        commands.append(String(decoding: data, as: UTF8.self))
    }

    /// 次の応答を返します。
    ///
    /// 責務: 予約の先頭を返し、尽きていれば応答期限切れを送出します。
    /// - Returns: 応答データ。
    /// - Throws: 応答が尽きた場合は `VehicleIdentificationError.responseTimedOut`。
    func readUntilPrompt() async throws -> Data {
        guard !responses.isEmpty else { throw VehicleIdentificationError.responseTimedOut }
        return Data(responses.removeFirst().utf8)
    }

    /// `close` を記録します。
    ///
    /// 責務: 閉じた回数を数えます。
    func close() async {
        closeCount += 1
    }
}

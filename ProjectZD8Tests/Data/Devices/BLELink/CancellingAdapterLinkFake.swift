import Foundation
@testable import ProjectZD8

/// 指定したコマンドの書き込み中に、書き込んでいるタスク自身を取り消すリンクの fake です。
///
/// 応答は書き込みの中で同期的に返すため、取り消しの時点で応答はすでに受信済みになります
/// (「書き込み中に取り消しが来た」状況を作り、次のコマンドを送らないことを検証するため)。
@MainActor
final class CancellingAdapterLinkFake: AdapterLinkPort {
    /// 現在のリンク状態です。
    var state: AdapterLinkState = .ready

    /// リンク状態の変化の通知先です。
    var stateDidChange: (@MainActor (AdapterLinkState) -> Void)?

    /// 受信データの通知先です。
    var dataDidReceive: (@MainActor (Data) -> Void)?

    /// コマンド(大文字・改行なし)ごとの応答です。無いコマンドには応答しません。
    var replies: [String: String] = [:]

    /// 書き込み中のタスクを取り消すコマンドです。`nil` なら取り消しません。
    var cancellingCommand: String?

    /// 書き込まれたコマンドを順に記録します。
    private(set) var writtenCommands: [String] = []

    /// 責務: リンクの開始要求を受け付けます(このテストでは何もしません)。
    /// - Parameter preference: 使用しない既定アダプター設定。
    func start(preference: DefaultAdapterPreference) {}

    /// 責務: リンクの停止要求を受け付けます(このテストでは何もしません)。
    func stop() {}

    /// コマンドを記録し、必要なら書き込み中のタスクを取り消してから応答を返します。
    ///
    /// 責務: 取り消しと応答受信が同じ書き込みの中で起きる状況を作ります。
    /// - Parameter data: 書き込むバイト列。
    /// - Throws: リンクが `ready` でない場合は `AdapterLinkWriteError.notReady`。
    func write(_ data: Data) async throws {
        guard state == .ready else { throw AdapterLinkWriteError.notReady }
        let command = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
            .uppercased()
        writtenCommands.append(command)
        if command == cancellingCommand {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        if let reply = replies[command] {
            dataDidReceive?(Data(reply.utf8))
        }
    }
}

import Foundation
@testable import ProjectZD8

/// コマンドごとに台本どおりの応答を返す、テスト用のバイトストリームTransportです。
@MainActor
final class DevicesScriptedOBDTransport: OBDCommandTransport {
    /// 1回の読取で返す結果です。
    enum Step: Sendable {
        /// 応答文字列(`>` は自動で付きます)。
        case response(String)
        /// 読取期限切れ。
        case timeout
        /// 通信断。
        case failure
        /// 1回目の読取で遅延応答(`stale`)を返し、2回目で本来の応答(`actual`)を返す。
        case lateResponse(stale: String, actual: String)
    }

    /// 書き込まれたコマンド(復帰文字なし)の履歴です。
    private(set) var writtenCommands: [String] = []
    /// `open()` が呼ばれた回数です。
    private(set) var openCount = 0
    /// `close()` が呼ばれた回数です。
    private(set) var closeCount = 0
    /// 次の読取以降で返す結果です。
    private var pending: [Step] = []
    /// コマンドごとの結果キューです。空なら `defaultStep` を使います。
    private var scripts: [String: [Step]]
    /// 台本に無いコマンドへの既定の結果です。
    private let defaultStep: Step
    /// `open()` を失敗させるときのエラーです。
    private let openError: OBDTransportError?

    /// 台本つきのTransportを生成します。
    ///
    /// 責務: コマンドから応答への対応表を固定したテスト用Transportを構築します。
    /// - Parameters:
    ///   - scripts: コマンド(復帰文字なし)から、順に消費する結果の配列への対応表。
    ///   - defaultStep: 台本に無い、または使い切ったコマンドへの結果。
    ///   - openError: 指定すると `open()` がこのエラーを投げます。
    init(scripts: [String: [Step]] = [:], defaultStep: Step = .response("OK"), openError: OBDTransportError? = nil) {
        self.scripts = scripts
        self.defaultStep = defaultStep
        self.openError = openError
    }

    /// 責務: 開通を記録します。`openError` があれば投げます。
    func open() async throws {
        openCount += 1
        if let openError { throw openError }
    }

    /// 責務: コマンドを記録し、次の読取で返す結果を台本から取り出します。
    func write(_ data: Data) async throws {
        let command = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        writtenCommands.append(command)
        let step: Step
        if var queue = scripts[command], !queue.isEmpty {
            step = queue.removeFirst()
            scripts[command] = queue
        } else {
            step = defaultStep
        }
        switch step {
        case let .lateResponse(stale, actual):
            pending = [.response(stale), .response(actual)]
        case .failure:
            throw OBDTransportError.connectionFailed
        default:
            pending = [step]
        }
    }

    /// 責務: 台本の結果を返します。
    func readUntilPrompt() async throws -> Data {
        guard !pending.isEmpty else { throw OBDTransportError.timedOut }
        switch pending.removeFirst() {
        case let .response(text):
            return Data((text + "\r\r>").utf8)
        case .timeout:
            throw OBDTransportError.timedOut
        case .failure, .lateResponse:
            throw OBDTransportError.connectionFailed
        }
    }

    /// 責務: 閉鎖を記録します。
    func close() async {
        closeCount += 1
    }
}

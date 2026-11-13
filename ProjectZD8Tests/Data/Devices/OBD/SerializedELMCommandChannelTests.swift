import Foundation
import XCTest
@testable import ProjectZD8

/// ELMコマンド直列化境界の応答保持と境界喪失を検証します。
final class SerializedELMCommandChannelTests: XCTestCase {
    /// プロンプトだけを除いて加工前応答を返します。
    ///
    /// 責務: 許可済みコマンドが1回送信され応答本文が保持されることを確認します。
    func testExecuteWritesCommandAndReturnsResponseWithoutPrompt() async throws {
        let transport = SerializedChannelTransportFake(result: .success(Data("OK\r>".utf8)))
        let channel = SerializedELMCommandChannel(transport: transport)

        let response = try await channel.execute(ELM327Command.echoOff)

        XCTAssertEqual(response, "OK\r")
        let commands = await transport.commands
        XCTAssertEqual(commands, ["ATE0\r"])
    }

    /// 応答境界を失った接続を暗黙再利用しません。
    ///
    /// 責務: 最初のread失敗後は後続コマンドをTransportへ書き込まないことを確認します。
    func testExecuteRejectsSubsequentCommandAfterReadFailure() async {
        let transport = SerializedChannelTransportFake(result: .failure(VehicleIdentificationError.responseTimedOut))
        let channel = SerializedELMCommandChannel(transport: transport)

        do {
            _ = try await channel.execute(ELM327Command.echoOff)
            XCTFail("read失敗は成功してはいけません")
        } catch {
            XCTAssertEqual(error as? VehicleIdentificationError, .responseTimedOut)
        }

        do {
            _ = try await channel.execute(ELM327Command.linefeedsOff)
            XCTFail("境界喪失後の再利用は成功してはいけません")
        } catch {
            XCTAssertEqual(error as? VehicleIdentificationError, .connectionFailed)
        }

        let commands = await transport.commands
        XCTAssertEqual(commands, ["ATE0\r"])
    }
}

/// 直列チャネルへ固定応答または固定エラーを返すTransportです。
private actor SerializedChannelTransportFake: OBDCommandTransport {
    /// read時に返す固定結果です。
    private let result: Result<Data, Error>
    /// 書込み済みASCIIコマンドです。
    private(set) var commands: [String] = []

    /// read結果を固定して生成します。
    ///
    /// 責務: 1件の送受信シナリオへread結果を固定します。
    /// - Parameter result: read時に返すデータまたはエラー。
    init(result: Result<Data, Error>) {
        self.result = result
    }

    /// Fakeでは追加資源を確保せずopenを完了します。
    ///
    /// 責務: 直列チャネルテスト用Transportを利用可能状態として扱います。
    func open() async throws {}

    /// ASCIIコマンドを履歴へ記録します。
    ///
    /// 責務: 1件の書込みデータを検証可能な文字列として保存します。
    /// - Parameter data: 送信されたASCIIデータ。
    func write(_ data: Data) async throws {
        guard let command = String(data: data, encoding: .utf8) else {
            throw VehicleIdentificationError.malformedResponse
        }
        commands.append(command)
    }

    /// 固定したread結果を返します。
    ///
    /// 責務: 現在シナリオの応答または失敗を1件返します。
    /// - Returns: プロンプトを含む加工前応答。
    func readUntilPrompt() async throws -> Data {
        try result.get()
    }

    /// Fakeでは資源を持たずcloseを完了します。
    ///
    /// 責務: 直列チャネルテスト用Transportを終了済みとして扱います。
    func close() async {}
}

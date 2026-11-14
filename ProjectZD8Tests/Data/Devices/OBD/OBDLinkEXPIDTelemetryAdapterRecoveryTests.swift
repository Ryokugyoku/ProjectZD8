import Foundation
import XCTest
@testable import ProjectZD8

/// OBDLink EX アダプターの回復操作(プロンプト再同期・ATZ再初期化・再接続)を、応答を予約したTransportで検証します。
@MainActor
final class OBDLinkEXPIDTelemetryAdapterRecoveryTests: XCTestCase {
    /// 初期化と送信ヘッダー設定と1件のPIDに対する応答です。
    private let sessionResponses = ["ELM327 v1.4b\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>", "41 0C 1F 40\r>"]
    /// 初期化(ATZ〜ATSP0)の応答です。
    private let initializationResponses = ["ELM327 v1.4b\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>"]
    /// 初期化で送るコマンドです。
    private let initializationCommands: [ELM327Command] = [.reset, .echoOff, .linefeedsOff, .spacesOn, .headersOff, .automaticProtocol]

    /// 接続していない、または別の終端では、プロンプト再同期はリンク利用不能で失敗し、Transportを作りません。
    ///
    /// 責務: 開いた接続が無い場合の失敗を確認します。
    func testPromptResyncWithoutActiveLinkIsUnavailable() async throws {
        let queue = OBDCommandTransportQueue([ScriptedOBDCommandTransportFake(responses: sessionResponses)])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in try queue.next() })

        await assertRecoveryError(.linkUnavailable) { try await adapter.promptResync(using: self.endpoint) }
        XCTAssertEqual(queue.makeCount, 0)
        _ = try await adapter.readObservations([request], using: endpoint)
        await assertRecoveryError(.linkUnavailable) { try await adapter.promptResync(using: self.otherEndpoint) }
    }

    /// 開いた接続のプロンプト再同期は ATI を送り、同じTransportを閉じずに使い続けます。
    ///
    /// 責務: 再同期の送信コマンドと、再同期後の要求が同じTransportで送られることを確認します。
    func testPromptResyncKeepsTransport() async throws {
        let transport = ScriptedOBDCommandTransportFake(responses: sessionResponses)
        let queue = OBDCommandTransportQueue([transport])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in try queue.next() })
        _ = try await adapter.readObservations([request], using: endpoint)
        transport.append(["ELM327 v1.4b\r>", "41 0C 1F 41\r>"])

        try await adapter.promptResync(using: endpoint)
        let observations = try await adapter.readObservations([request], using: endpoint)

        XCTAssertEqual(transport.commands.suffix(2).first, text(.adapterIdentity))
        XCTAssertEqual(observations, [.init(request: request, outcome: .responded([0x1F, 0x41]))])
        XCTAssertEqual(queue.makeCount, 1)
        XCTAssertEqual(transport.closeCount, 0)
    }

    /// プロンプト再同期の応答が識別応答でない、または届かなければ、回復の期限切れで失敗します。
    ///
    /// 責務: 再同期の失敗の分類を確認します。
    func testPromptResyncFailuresAreTimedOut() async throws {
        for extra in [["NO DATA\r>", "?\r>"], []] {
            let transport = ScriptedOBDCommandTransportFake(responses: sessionResponses)
            let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in transport })
            _ = try await adapter.readObservations([request], using: endpoint)
            transport.append(extra)

            await assertRecoveryError(.timedOut) { try await adapter.promptResync(using: self.endpoint) }
        }
    }

    /// 開いた接続のATZ再初期化は同じTransportで初期化手順を送り直し、次の要求で送信ヘッダーを設定し直します。
    ///
    /// 責務: 再初期化の送信コマンドと、Transportを作り直さないことを確認します。
    func testReinitializeFromResetReusesTransport() async throws {
        let transport = ScriptedOBDCommandTransportFake(responses: sessionResponses)
        let queue = OBDCommandTransportQueue([transport])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in try queue.next() })
        _ = try await adapter.readObservations([request], using: endpoint)
        let before = transport.commands.count
        transport.append(initializationResponses + ["OK\r>", "41 0C 00 10\r>"])

        try await adapter.reinitializeFromReset(using: endpoint)
        _ = try await adapter.readObservations([request], using: endpoint)

        XCTAssertEqual(Array(transport.commands[before..<(before + 6)]), initializationCommands.map(text))
        XCTAssertEqual(transport.commands.filter { $0.hasPrefix("ATSH") }.count, 2)
        XCTAssertEqual(queue.makeCount, 1)
        XCTAssertEqual(transport.closeCount, 0)
    }

    /// ATZ再初期化で拒否応答を受けると、回復の拒否で失敗します。
    ///
    /// 責務: 再初期化の拒否の分類を確認します。
    func testReinitializeFromResetRejected() async throws {
        let transport = ScriptedOBDCommandTransportFake(responses: sessionResponses)
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in transport })
        _ = try await adapter.readObservations([request], using: endpoint)
        transport.append(["?\r>"])

        await assertRecoveryError(.rejected) { try await adapter.reinitializeFromReset(using: self.endpoint) }
    }

    /// 開いた接続が無い時のATZ再初期化は再接続として新しいTransportを開いて初期化します。
    ///
    /// 責務: 再初期化から再接続への切替を確認します。
    func testReinitializeWithoutActiveLinkReconnects() async throws {
        let transport = ScriptedOBDCommandTransportFake(responses: initializationResponses)
        let queue = OBDCommandTransportQueue([transport])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in try queue.next() })

        try await adapter.reinitializeFromReset(using: endpoint)

        XCTAssertEqual(queue.makeCount, 1)
        XCTAssertEqual(transport.openCount, 1)
        XCTAssertEqual(transport.commands, initializationCommands.map(text))
    }

    /// 再接続は開いた接続を閉じ、新しいTransportを開いて初期化し、初期化の応答が届かなければ回復の期限切れで失敗します。
    ///
    /// 責務: 再接続の閉じ・開き・初期化と、失敗の分類を確認します。
    func testReconnectLinkReplacesTransport() async throws {
        let first = ScriptedOBDCommandTransportFake(responses: sessionResponses)
        let second = ScriptedOBDCommandTransportFake(responses: initializationResponses)
        let third = ScriptedOBDCommandTransportFake(responses: [])
        let queue = OBDCommandTransportQueue([first, second, third])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in try queue.next() })
        _ = try await adapter.readObservations([request], using: endpoint)

        try await adapter.reconnectLink(using: endpoint)
        await assertRecoveryError(.timedOut) { try await adapter.reconnectLink(using: self.endpoint) }

        XCTAssertEqual(first.closeCount, 1)
        XCTAssertEqual(second.openCount, 1)
        XCTAssertEqual(second.commands, initializationCommands.map(text))
        XCTAssertEqual(queue.makeCount, 3)
    }

    /// 処理が指定の回復エラーを送出することを検証します。
    ///
    /// 責務: 送出されたエラーのcaseを確認し、成功した場合は失敗させます。
    /// - Parameters:
    ///   - expected: 期待する回復エラー。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    ///   - operation: 検証する処理。
    private func assertRecoveryError(
        _ expected: LiveTelemetryLinkRecoveryError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("\(expected) を期待しましたが成功しました", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? LiveTelemetryLinkRecoveryError, expected, file: file, line: line)
        }
    }

    /// コマンドの送信文字列を返します。
    ///
    /// 責務: 符号化済みコマンドをUTF-8の文字列へ変換します。
    /// - Parameter command: コマンド。
    /// - Returns: 送信文字列。
    private func text(_ command: ELM327Command) -> String {
        String(decoding: command.encodedData, as: UTF8.self)
    }

    /// テスト用の要求です。
    private var request: OBDPIDRequest { OBDPIDRequest(service: 0x01, pid: 0x0C) }

    /// テスト用EXシリアル終端です。
    private var endpoint: OBDConnectionEndpoint {
        OBDConnectionEndpoint(transport: .serial, systemIdentifier: "/dev/cu.fake", displayName: "OBDLink EX")
    }

    /// 開いた接続とは別の終端です。
    private var otherEndpoint: OBDConnectionEndpoint {
        OBDConnectionEndpoint(transport: .serial, systemIdentifier: "/dev/cu.other", displayName: "Other")
    }
}

import XCTest
@testable import ProjectZD8

/// `AdapterLinkELMInitializer` が通信失敗を throw し、証跡を返さないことを検証します。
@MainActor
final class AdapterLinkELMInitializerFailureTests: XCTestCase {
    /// 台本を調整したアダプターで初期化を実行します。
    ///
    /// 責務: STN として初期化できる台本を組み、調整後に `initializeAdapter()` を上限付きで待ちます。
    /// - Parameter configure: 実行前に台本を調整する処理。
    /// - Returns: 使ったハーネスと結果。
    private func initialize(
        configure: (ScriptedAdapterLinkFake) -> Void
    ) async -> (AdapterLinkByteStreamHarness, Result<AcquisitionAdapterProbeEvidence, any Error>?) {
        let harness = AdapterLinkByteStreamHarness()
        harness.link.replies = AdapterLinkELMReplyFixtures.initializableAdapter(
            stnIdentity: AdapterLinkELMReplyFixtures.stnIdentity,
            adapterIdentity: AdapterLinkELMReplyFixtures.elmVersion15
        )
        harness.link.monitorOutput = AdapterLinkELMReplyFixtures.monitorFrames
        configure(harness.link)
        let initializer = AdapterLinkELMInitializer(stream: harness.stream)
        let outcome = await AdapterLinkBoundedAwait.run("アダプター初期化") { try await initializer.initializeAdapter() }
        return (harness, outcome)
    }

    /// 失敗で終わったことを確かめます。
    ///
    /// 責務: 成功(証跡を返した)・未完了を失敗として報告し、エラーを返します。
    /// - Parameter outcome: 初期化の結果。
    /// - Returns: 投げられたエラー。
    private func thrownError(
        _ outcome: Result<AcquisitionAdapterProbeEvidence, any Error>?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (any Error)? {
        guard let outcome else { return nil }
        switch outcome {
        case .success(let evidence):
            XCTFail("通信失敗なのに証跡を返しました: \(evidence)", file: file, line: line)
            return nil
        case .failure(let error):
            return error
        }
    }

    /// 識別の問い合わせ中にリンクが切断されると throw します。
    ///
    /// 責務: `STI` 送信時の切断で証跡を返さずリンク喪失(`.linkLost`)で失敗し、リンクを開始も停止もしないことを確認します。
    func testDisconnectDuringIdentityThrows() async {
        let (harness, outcome) = await initialize { link in
            link.disconnectingCommands = ["STI"]
        }
        XCTAssertEqual(thrownError(outcome) as? AdapterLinkByteStreamError, .linkLost, "切断は期限切れと区別できるエラーになる")
        XCTAssertEqual(harness.link.startCount + harness.link.stopCount, 0)
    }

    /// 識別の応答が来なければ期限切れで throw し、その後の利用者はリンクを使えます。
    ///
    /// 責務: `ATI` 無応答で `.responseTimedOut` になり、占有権が解放されて続く車両確認が応答を得ることを確認します。
    func testIdentityTimeoutThrowsAndReleasesLink() async {
        let (harness, outcome) = await initialize { link in
            link.replies["ATI"] = nil
        }
        XCTAssertEqual(thrownError(outcome) as? AdapterLinkByteStreamError, .responseTimedOut)

        let confirmer = AdapterLinkVehicleResponseConfirmer(stream: harness.stream)
        let confirmation = await AdapterLinkBoundedAwait.run("失敗後の車両確認") {
            try await confirmer.confirmVehicleResponse(timeout: .standard)
        }
        XCTAssertEqual(AdapterLinkBoundedAwait.successValue(confirmation), .responding)
    }

    /// リセットに応答が無ければ throw します。
    ///
    /// 責務: 最初のコマンドの無応答で証跡を返さないことを確認します。
    func testResetTimeoutThrows() async {
        let (_, outcome) = await initialize { link in
            link.replies["ATZ"] = nil
        }
        XCTAssertEqual(thrownError(outcome) as? AdapterLinkByteStreamError, .responseTimedOut)
    }

    /// 受信監視を止めても応答が戻らなければ、成功にせず throw します。
    ///
    /// 責務: 監視停止後にプロンプトが来ない場合に証跡を返さず、期限切れ(`.responseTimedOut`)で失敗することを確認します。
    func testMonitorThatNeverStopsThrows() async {
        let (_, outcome) = await initialize { link in
            link.monitorStopReply = nil
        }
        XCTAssertEqual(thrownError(outcome) as? AdapterLinkByteStreamError, .responseTimedOut, "応答待ちの期限切れになる")
    }
}

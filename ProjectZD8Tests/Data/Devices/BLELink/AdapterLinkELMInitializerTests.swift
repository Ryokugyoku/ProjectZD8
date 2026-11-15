import XCTest
@testable import ProjectZD8

/// `AdapterLinkELMInitializer` のコマンド順・チップ判定・ATMA判定・失敗時の振る舞いを検証します。
@MainActor
final class AdapterLinkELMInitializerTests: XCTestCase {
    /// 取得モード(受信監視・受信フィルター)を切り替えるコマンドの接頭辞です。
    private static let modeSwitchingPrefixes = ["STM", "STF", "ATCRA", "ATCF", "ATCM", "ATSH", "ATMR", "ATMT"]

    /// 指定した識別応答を返すアダプターで初期化を実行します。
    ///
    /// 責務: 台本を組んだハーネスで `initializeAdapter()` を上限付きで待ちます。
    /// - Parameters:
    ///   - stnIdentity: `STI` への応答。
    ///   - adapterIdentity: `ATI` への応答。
    ///   - configure: 実行前に台本を調整する処理。
    /// - Returns: 使ったハーネスと結果。
    private func initialize(
        stnIdentity: String,
        adapterIdentity: String,
        configure: (ScriptedAdapterLinkFake) -> Void = { _ in }
    ) async -> (AdapterLinkByteStreamHarness, Result<AcquisitionAdapterProbeEvidence, any Error>?) {
        let harness = AdapterLinkByteStreamHarness()
        harness.link.replies = AdapterLinkELMReplyFixtures.initializableAdapter(stnIdentity: stnIdentity, adapterIdentity: adapterIdentity)
        harness.link.monitorOutput = AdapterLinkELMReplyFixtures.monitorFrames
        configure(harness.link)
        let initializer = AdapterLinkELMInitializer(stream: harness.stream)
        let outcome = await AdapterLinkBoundedAwait.run("アダプター初期化") { try await initializer.initializeAdapter() }
        return (harness, outcome)
    }

    /// リセットとエコーオフの後に STN 識別、ELM 識別の順で問い合わせます。
    ///
    /// 責務: 最初の送信がリセットで、エコーオフが識別より前、STN 識別が ELM 識別より前であることを確認します。
    func testInitializationQueriesIdentitiesAfterResetAndEchoOff() async throws {
        let (harness, outcome) = await initialize(
            stnIdentity: AdapterLinkELMReplyFixtures.stnIdentity,
            adapterIdentity: AdapterLinkELMReplyFixtures.elmVersion15
        )
        _ = AdapterLinkBoundedAwait.successValue(outcome)
        let commands = harness.link.writtenCommands
        XCTAssertEqual(commands.first, "ATZ")
        let echoOff = try XCTUnwrap(commands.firstIndex(of: "ATE0"))
        let stn = try XCTUnwrap(commands.firstIndex(of: "STI"))
        let elm = try XCTUnwrap(commands.firstIndex(of: "ATI"))
        XCTAssertLessThan(echoOff, stn)
        XCTAssertLessThan(stn, elm)
    }

    /// 識別応答ごとにチップ種別を判定し、拡張プローブは方針が要求した時だけ送ります。
    ///
    /// 責務: STN・クローン版数・v2.1+拡張プローブ受付/拒否・不明の各場合のチップ種別と `ATPPS` 送信有無を確認します。
    func testChipFamilyAndExtendedProbeFollowClassificationPolicy() async {
        let cases: [(name: String, sti: String, ati: String, probe: String?, family: OBDAdapterChipFamily, probes: Bool)] = [
            ("STN", AdapterLinkELMReplyFixtures.stnIdentity, AdapterLinkELMReplyFixtures.elmVersion15, nil, .stn, false),
            ("ELM v1.5", AdapterLinkELMReplyFixtures.rejected, AdapterLinkELMReplyFixtures.elmVersion15, nil, .elm327Clone, false),
            ("ELM v2.1 受付", AdapterLinkELMReplyFixtures.rejected, AdapterLinkELMReplyFixtures.elmVersion21, "PP 00 FF\r\r>", .elm327Genuine, true),
            ("ELM v2.1 拒否", AdapterLinkELMReplyFixtures.rejected, AdapterLinkELMReplyFixtures.elmVersion21, "?\r\r>", .elm327Clone, true),
            ("不明", AdapterLinkELMReplyFixtures.rejected, "OBDII to RS232\r\r>", nil, .unknown, false)
        ]
        for testCase in cases {
            let (harness, outcome) = await initialize(stnIdentity: testCase.sti, adapterIdentity: testCase.ati) { link in
                link.replies["ATPPS"] = testCase.probe
            }
            let evidence = AdapterLinkBoundedAwait.successValue(outcome)
            XCTAssertEqual(evidence?.chipFamily, testCase.family, testCase.name)
            XCTAssertEqual(harness.link.writtenCommands.contains("ATPPS"), testCase.probes, testCase.name)
        }
    }

    /// ATMA でフレームを受信すれば「対応あり」、`?` なら「対応なし」として証跡に入ります。
    ///
    /// 責務: 受信監視の応答ごとの `monitorProbeOutcome` を確認します。
    func testMonitorProbeOutcomeReflectsAtmaResponse() async {
        let (framesHarness, frames) = await initialize(
            stnIdentity: AdapterLinkELMReplyFixtures.stnIdentity,
            adapterIdentity: AdapterLinkELMReplyFixtures.elmVersion15
        )
        XCTAssertEqual(AdapterLinkBoundedAwait.successValue(frames)?.monitorProbeOutcome, .framesReceived)
        XCTAssertTrue(framesHarness.link.writtenCommands.contains("ATMA"))

        let (_, rejected) = await initialize(
            stnIdentity: AdapterLinkELMReplyFixtures.stnIdentity,
            adapterIdentity: AdapterLinkELMReplyFixtures.elmVersion15
        ) { link in
            link.monitorOutput = nil
            link.replies["ATMA"] = AdapterLinkELMReplyFixtures.rejected
        }
        XCTAssertEqual(AdapterLinkBoundedAwait.successValue(rejected)?.monitorProbeOutcome, .unsupported)
    }

    /// 判定できない ATMA 応答は「対応あり」にしません。
    ///
    /// 責務: 無意味な受信・無受信のどちらも、対応ありを表す `.framesReceived`・`.bufferFull` にならないことを確認します。
    func testUndeterminableAtmaResponseIsNotTreatedAsSupported() async {
        for output in ["GARBAGE XYZ\r", ""] {
            let (_, outcome) = await initialize(
                stnIdentity: AdapterLinkELMReplyFixtures.stnIdentity,
                adapterIdentity: AdapterLinkELMReplyFixtures.elmVersion15
            ) { link in
                link.monitorOutput = output
            }
            let monitorOutcome = AdapterLinkBoundedAwait.successValue(outcome)?.monitorProbeOutcome
            XCTAssertNotNil(monitorOutcome, "出力: \(output)")
            XCTAssertNotEqual(monitorOutcome, .framesReceived, "出力: \(output)")
            XCTAssertNotEqual(monitorOutcome, .bufferFull, "出力: \(output)")
        }
    }

    /// ATMA の監視は判定後に止められ、その後のコマンドは通常どおり応答を受け取ります。
    ///
    /// 責務: 初期化完了時に監視が止まり、監視中に送られて応答を失ったコマンドが無く、続く車両確認が `0100` の応答を受け取ることを確認します。
    func testMonitorIsStoppedAndLaterCommandsReceiveResponses() async {
        let (harness, outcome) = await initialize(
            stnIdentity: AdapterLinkELMReplyFixtures.stnIdentity,
            adapterIdentity: AdapterLinkELMReplyFixtures.elmVersion15
        )
        _ = AdapterLinkBoundedAwait.successValue(outcome)
        XCTAssertFalse(harness.link.isMonitoring, "初期化後に受信監視が続いていてはいけない")
        XCTAssertEqual(harness.link.commandsSwallowedByMonitor, [], "監視の停止に通常のコマンドを使うと、そのコマンドの応答が得られない")

        let confirmer = AdapterLinkVehicleResponseConfirmer(stream: harness.stream)
        let confirmation = await AdapterLinkBoundedAwait.run("初期化後の車両確認") {
            try await confirmer.confirmVehicleResponse(timeout: .standard)
        }
        XCTAssertEqual(AdapterLinkBoundedAwait.successValue(confirmation), .responding)
    }

    /// 取得モードを切り替えるコマンドは送りません。
    ///
    /// 責務: 初期化中の全送信に受信監視モード・受信フィルター・送信ヘッダーの設定が含まれないことを確認します。
    func testInitializationDoesNotSendModeSwitchingCommands() async {
        let (harness, outcome) = await initialize(
            stnIdentity: AdapterLinkELMReplyFixtures.rejected,
            adapterIdentity: AdapterLinkELMReplyFixtures.elmVersion21
        ) { link in
            link.replies["ATPPS"] = "PP 00 FF\r\r>"
        }
        _ = AdapterLinkBoundedAwait.successValue(outcome)
        let switching = harness.link.writtenCommands.filter { command in
            Self.modeSwitchingPrefixes.contains { command.hasPrefix($0) }
        }
        XCTAssertEqual(switching, [])
    }
}

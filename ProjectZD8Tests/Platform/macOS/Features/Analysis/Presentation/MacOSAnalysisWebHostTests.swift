#if os(macOS)
import WebKit
import XCTest
@testable import ProjectZD8

/// 実際のWebKit上で、同梱ワークベンチが独自スキームから起動し、ホストからのデータで描画されることを検証します。
@MainActor
final class MacOSAnalysisWebHostTests: XCTestCase {
    private typealias F = AnalysisFixtures

    /// 責務: 実データ相当のデータセットをストアへ置いたホストを作ります。
    private func makeHost() async throws -> (MacOSAnalysisWebHost, AnalysisState, AnalysisDatasetStore, [AnalysisActionBox]) {
        let vehicle = F.vehicle(name: "Bridge Car")
        let sessions = AnalysisFakeSessionRepository()
        let useCase = BuildAnalysisDatasetUseCase(
            decoder: AnalysisSessionDecoder(sessions: sessions),
            vehicles: AnalysisFakeVehicleRepository([vehicle]),
            maintenance: AnalysisFakeMaintenanceRepository(),
            names: AnalysisFakeNameResolver()
        )
        let session = F.session(vehicleID: vehicle.id, duration: 60, sampleCount: 120)
        var samples: [SessionSample] = []
        for second in 0..<60 {
            samples.append(F.sample(Int64(samples.count), seconds: Double(second), F.speed, payload: [UInt8(min(second * 3, 120))]))
            samples.append(F.sample(Int64(samples.count), seconds: Double(second), F.rpm, payload: [0x1F, 0x40]))
        }
        await sessions.seed(session, pids: F.standardPIDs(), samples: samples)
        let dataset = try await useCase.build(sessionID: session.id)
        let store = AnalysisDatasetStore()
        let path = AnalysisDatasetStore.datasetPath(for: session.id)
        store.set(try await AnalysisJSONEncoder.encode(dataset), forPath: path)

        var state = AnalysisState(languageCode: "en")
        state.loadedSessions = [AnalysisLoadedSession(id: session.id, datasetPath: path, vehicleName: vehicle.name, startedAt: session.startedAt, isDemo: false)]
        state.phase = .ready
        let box = AnalysisActionBox()
        let content = ResolveAnalysisWebContentUseCase(resourceDirectory: try XCTUnwrap(Bundle(for: AnalysisDatasetStore.self).resourceURL), store: store)
        let host = MacOSAnalysisWebHost(content: content) { box.actions.append($0) }
        return (host, state, store, [box])
    }

    /// 責務: 条件が満たされるまでページ内でスクリプトを繰り返し評価して待ちます。
    private func waitFor(_ host: MacOSAnalysisWebHost, script: String, timeout: TimeInterval = 20) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let ok = try? await host.page.callJavaScript(script) as? Bool, ok { return true }
            try await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    /// 責務: ページが起動して `ready` を通知し、設定メッセージで車両名とKPIが描画されることを確認します。
    func testWorkbenchBootsFromCustomSchemeAndRendersDataset() async throws {
        let (host, state, _, _) = try await makeHost()
        defer { host.tearDown() }
        let deadline = Date().addingTimeInterval(20)
        while !host.isWebReady && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(host.isWebReady, "モジュールの読み込みと ready の通知まで進む(CSP・スキーム配信・メッセージ経路)")

        await host.push(state)
        let rendered = try await waitFor(host, script: "return document.querySelectorAll('.kpis .kpi').length >= 8 && document.querySelector('.session-chips').textContent.includes('Bridge Car');")
        XCTAssertTrue(rendered, "fetchで取得したデータセットでKPIが描画される")
        let language = try await host.page.callJavaScript("return document.documentElement.lang") as? String
        XCTAssertEqual(language, "en")
    }

    /// 責務: Webからの書き出し要求がネイティブの操作として届くこと、外部への遷移が拒否されることを確認します。
    func testBridgeDeliversActionsAndBlocksNavigation() async throws {
        let (host, _, _, boxes) = try await makeHost()
        defer { host.tearDown() }
        let deadline = Date().addingTimeInterval(20)
        while !host.isWebReady && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(host.isWebReady)

        _ = try await host.page.callJavaScript("window.webkit.messageHandlers.analysisBridge.postMessage({ type: 'export', filename: 'a.csv', mimeType: 'text/csv', base64: btoa('x,y') }); window.webkit.messageHandlers.analysisBridge.postMessage({ type: 'nonsense' }); window.webkit.messageHandlers.analysisBridge.postMessage({ type: 'requestSession' }); return true")
        try await Task.sleep(for: .milliseconds(500))
        let actions = boxes[0].actions
        XCTAssertEqual(actions.count, 2, "不正なメッセージは無視される")
        guard case .receiveExport(let request) = actions[0] else { return XCTFail("exportのはず") }
        XCTAssertEqual(request.data, Data("x,y".utf8))
        XCTAssertEqual(actions[1], .requestSessionPicker(.addComparison))

        let before = host.page.url
        _ = try? await host.page.callJavaScript("location.href = 'https://example.com/'; return true")
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(host.page.url?.scheme, before?.scheme, "アプリのスキーム以外へは遷移しない")
    }
}

/// テスト用に、ホストから届いた操作を貯める箱です。
@MainActor
final class AnalysisActionBox {
    var actions: [AnalysisAction] = []
}
#endif

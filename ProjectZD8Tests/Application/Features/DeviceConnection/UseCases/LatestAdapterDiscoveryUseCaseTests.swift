import XCTest
@testable import ProjectZD8

/// 最新要求だけを通知するアダプター探索ライフサイクルを検証します。
@MainActor
final class LatestAdapterDiscoveryUseCaseTests: XCTestCase {
    /// キャンセルを無視する古い探索完了が通知されないことを検証します。
    ///
    /// 責務: 再探索後は最新世代の候補だけが完了通知へ到達することを確認します。
    func testStartRejectsResultFromPreviousGeneration() async {
        let oldAdapter = makeAdapter(id: "old")
        let currentAdapter = makeAdapter(id: "current")
        let port = ControlledLatestDiscoveryPortFake()
        let useCase = makeUseCase(port: port)
        var outcomes: [AdapterDiscoveryOutcome] = []

        useCase.start(for: .bluetooth) { outcomes.append($0) }
        await waitForRequestCount(1, in: port)
        useCase.start(for: .bluetooth) { outcomes.append($0) }
        await waitForRequestCount(2, in: port)

        port.completeRequest(at: 1, with: [currentAdapter])
        for _ in 0..<40 where outcomes.isEmpty {
            await Task.yield()
        }
        port.completeRequest(at: 0, with: [oldAdapter])
        await Task.yield()

        XCTAssertEqual(outcomes, [.discovered([currentAdapter])])
    }

    /// 明示的な終了後に保留中の探索結果が通知されないことを検証します。
    ///
    /// 責務: 画面終了に相当するキャンセルが遅延完了の通知を拒否することを確認します。
    func testCancelRejectsPendingResult() async {
        let port = ControlledLatestDiscoveryPortFake()
        let useCase = makeUseCase(port: port)
        var outcomes: [AdapterDiscoveryOutcome] = []

        useCase.start(for: .bluetooth) { outcomes.append($0) }
        await waitForRequestCount(1, in: port)
        useCase.cancel()
        port.completeRequest(at: 0, with: [makeAdapter(id: "late")])
        await Task.yield()

        XCTAssertTrue(outcomes.isEmpty)
    }

    /// 指定ポートを利用する最新探索ユースケースを生成します。
    ///
    /// 責務: テスト用探索ポートを共通探索ライフサイクルへ結び付けます。
    /// - Parameter port: 完了順を制御する探索ポート。
    /// - Returns: 指定ポートを利用する最新探索ユースケース。
    private func makeUseCase(
        port: any AdapterDiscoveryPort
    ) -> LatestAdapterDiscoveryUseCase {
        LatestAdapterDiscoveryUseCase(
            discoverAdapters: DiscoverAdaptersUseCase(discoveryPort: port)
        )
    }

    /// 指定識別子を持つテスト用Bluetooth候補を生成します。
    ///
    /// 責務: 最新探索テストへ渡す最小のBluetooth候補を構築します。
    /// - Parameter id: 候補の安定識別子。
    /// - Returns: 未接続のBluetooth候補。
    private func makeAdapter(id: String) -> DiscoveredAdapter {
        DiscoveredAdapter(
            id: id,
            transportMode: .bluetooth,
            displayName: id,
            systemIdentifier: id,
            isConnected: false
        )
    }

    /// Fakeが指定件数の探索要求を受け取るまで待機します。
    ///
    /// 責務: テストで完了させる探索継続が登録されるまで限定回数待機します。
    /// - Parameters:
    ///   - expectedCount: 待機する探索要求件数。
    ///   - port: 要求数を監視する制御可能Fake。
    private func waitForRequestCount(
        _ expectedCount: Int,
        in port: ControlledLatestDiscoveryPortFake
    ) async {
        for _ in 0..<40 where port.requestCount < expectedCount {
            await Task.yield()
        }
        XCTAssertEqual(port.requestCount, expectedCount)
    }

}

/// 完了順をテストから制御できる最新探索用Fakeです。
@MainActor
private final class ControlledLatestDiscoveryPortFake: AdapterDiscoveryPort {
    /// 未完了の探索継続を要求順に保持します。
    private var continuations: [CheckedContinuation<[DiscoveredAdapter], Never>] = []

    /// 受け取った探索要求件数です。
    var requestCount: Int { continuations.count }

    /// テストから完了されるまで探索結果を保留します。
    ///
    /// 責務: 1件の探索要求を順序付き継続として記録します。
    /// - Parameter mode: 探索対象として要求された接続方式。
    /// - Returns: テストから指定された時点の候補一覧。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    /// 指定順の探索要求を候補一覧で完了します。
    ///
    /// 責務: 1件の保留中探索へテスト指定の候補一覧を返します。
    /// - Parameters:
    ///   - index: 完了する探索要求の順序。
    ///   - adapters: 探索結果として返す候補一覧。
    func completeRequest(at index: Int, with adapters: [DiscoveredAdapter]) {
        continuations[index].resume(returning: adapters)
    }
}

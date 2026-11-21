import Foundation
import XCTest
@testable import ProjectZD8

/// 古い世代の評価が `.noTrack` / `.noRegulationData` を返した時も、state に反映されないことを検証します(設計書 §6.3・§7 TC3)。
///
/// `.reviewed` は後段(内容の組み立ての後)でも世代を照合するため、ポートが返った直後の照合はこれらの結果でしか確かめられません。
/// 順序はポートの Fake を `RoadRegulationTestGate` で止めて作ります。1回目は取消に応じず、門が開いてから結果を返します。
@MainActor
final class SessionRoadRegulationReviewModelStaleOutcomeTests: XCTestCase {
    private typealias Values = SessionRoadRegulationReviewModelTestValues

    /// モデルと部品の組です。
    private var harness = SessionRoadRegulationReviewModelHarness()

    /// 責務: 止めた呼び出しを必ず再開し、終わらないテストを残しません。
    override func tearDown() async throws {
        harness.openAllGates()
        try await super.tearDown()
    }

    /// 責務: 結果 `result` を返す1回目の評価を門で止め(取消に応じない)、門の前で待つまで待ちます。
    /// - Parameter result: 1回目が返す結果。
    /// - Returns: 止めた門。
    private func startHeldEvaluation(returning result: SessionRoadRegulationReviewResult) async -> RoadRegulationTestGate? {
        let gate = harness.enqueue(.success(result), held: true, ignoresCancellation: true)
        harness.sendReadiness(.ready(.onDevice))
        await harness.waitForWaiting(on: gate)
        return gate
    }

    /// 責務: 1回目を止めたまま別のセッションの評価を loaded にし、1回目を再開して完了後も state が変わらないことを確かめます。
    /// - Parameters:
    ///   - staleResult: 1回目(古い世代)が返す結果。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    private func assertStaleOutcomeIgnoredAfterSwitching(
        _ staleResult: SessionRoadRegulationReviewResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let gate = await startHeldEvaluation(returning: staleResult)
        let other = ConnectionSessionID()
        await harness.load(Values.stopOnlyReview(), raw: .onDevice, session: other, file: file, line: line)
        let stateOfOther = harness.state

        gate?.open()
        await harness.waitForCompletion(ofCall: 0, file: file, line: line)
        await harness.settle()

        XCTAssertEqual(harness.state.status, .loaded, file: file, line: line)
        XCTAssertEqual(harness.state, stateOfOther, file: file, line: line)
        XCTAssertEqual(stateOfOther.sessionID, other, file: file, line: line)
        XCTAssertEqual(stateOfOther.summaries.map(\.total), [0, 1, 0, 0], file: file, line: line)
    }

    /// 責務: 古い世代の `.noTrack` が、切り替え先のセッションの loaded を上書きしないことを確かめます。
    func testStaleNoTrackAfterSwitchingIsDiscarded() async {
        await assertStaleOutcomeIgnoredAfterSwitching(.noTrack)
    }

    /// 責務: 古い世代の `.noRegulationData` が、切り替え先のセッションの loaded を上書きしないことを確かめます。
    func testStaleNoRegulationDataAfterSwitchingIsDiscarded() async {
        await assertStaleOutcomeIgnoredAfterSwitching(.noRegulationData)
    }

    /// 責務: 評価中に閉じた後で古い世代の `.noTrack` が届いても、state が初期のままであることを確かめます。
    func testStaleNoTrackAfterDismissIsDiscarded() async {
        let gate = await startHeldEvaluation(returning: .noTrack)

        harness.send(.dismissed)
        XCTAssertEqual(harness.state, SessionRoadRegulationReviewState())
        gate?.open()
        await harness.waitForCompletion(ofCall: 0)
        await harness.settle()

        XCTAssertEqual(harness.state, SessionRoadRegulationReviewState())
        XCTAssertEqual(harness.port.cancelledCalls, [0])
    }
}

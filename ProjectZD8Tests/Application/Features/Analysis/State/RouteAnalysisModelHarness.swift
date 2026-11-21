import Foundation
import XCTest
@testable import ProjectZD8

/// 解析の走行ルートのモデルを、ポートの Fake と既定の実物の部品で組み立て、期限つきの待ちを提供します。
///
/// 凡例の文字のロケールを固定するため、地図の層の部品だけロケールを渡して作ります。
@MainActor
final class RouteAnalysisModelHarness {
    /// 読み込みポートの Fake です。
    let port = RouteAnalysisTrackPortFake()
    /// 検証対象のモデルです。
    private(set) lazy var model = RouteAnalysisModel(
        trackPort: port,
        layerBuilder: RouteAnalysisMapLayerBuilder(legendBuilder: RouteAnalysisLegendBuilder(locale: Locale(identifier: "en_US")))
    )

    /// 部品を作ります。
    ///
    /// 責務: Fake を空の状態で用意します(モデルは最初の参照で作ります)。
    init() {}

    /// 現在の状態です。
    var state: RouteAnalysisState {
        model.state
    }

    /// 現在の線の分類の集合です。
    var lineCategories: Set<RouteAnalysisColorCategory> {
        Set(state.layers?.lines.map(\.category) ?? [])
    }

    /// セッションに読み込みの結果を置きます。
    ///
    /// 責務: ポートが返す結果を置き換えます。
    /// - Parameters:
    ///   - result: 返す結果。
    ///   - session: 対象のセッション。
    func setResult(_ result: RouteAnalysisTrackLoadResult, for session: ConnectionSession) {
        port.results[session.id] = result
    }

    /// 点のあるルートを置き、アカウントを渡してから表示し、色なしの線が出るまで待ちます。
    ///
    /// 責務: 読み込み済み(`ready` で層がある)の状態を期限つきで作ります。
    /// - Parameters:
    ///   - session: 表示するセッション。
    ///   - pointCount: ルートの点の数。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    func showReadyRoute(_ session: ConnectionSession, pointCount: Int = 10, file: StaticString = #filePath, line: UInt = #line) async {
        setResult(.available(RouteAnalysisModelTestValues.route(pointCount: pointCount), noticeKeys: []), for: session)
        model.send(.accountIdentifierChanged(RouteAnalysisModelTestValues.account))
        model.send(.sessionShown(session))
        await waitUntil("ready", file: file, line: line) {
            self.state.sessionID == session.id && self.state.phase == .ready && self.state.layers != nil
        }
    }

    /// 条件が成り立つまで期限(2秒)つきで待ちます。
    ///
    /// 責務: 既存の期限つきの待ちで条件を確かめ、成り立たなければテストを失敗させます。
    /// - Parameters:
    ///   - description: 失敗時に出す待機内容。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    ///   - condition: 待つ条件。
    func waitUntil(_ description: String, file: StaticString = #filePath, line: UInt = #line, condition: () -> Bool) async {
        await LocationRecordingBoundedWaiter.waitUntil(description, file: file, line: line, condition: condition)
    }

    /// 読み込みの呼び出しが指定件数になるまで待ちます。
    ///
    /// 責務: 期限(2秒)内に呼び出しの記録が届くのを待ち、届かなければテストを失敗させます。
    /// - Parameters:
    ///   - count: 待つ件数。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    func waitForCallCount(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        await waitUntil("load calls \(count)", file: file, line: line) { self.port.calls.count >= count }
    }

    /// 門で止まっている読み込みが指定件数になるまで待ちます。
    ///
    /// 責務: 期限(2秒)内に門の待ちが届くのを待ち、届かなければテストを失敗させます。
    /// - Parameters:
    ///   - count: 待つ件数。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    func waitForGateWaiting(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        await waitUntil("gate waiting \(count)", file: file, line: line) { self.port.gate.waitingCount >= count }
    }

    /// 指定のセッションの読み込みが完了を記録するまで待ち、その記録を返します。
    ///
    /// 責務: 期限(2秒)内に完了が記録されるのを待ち、なければテストを失敗させます。
    /// - Parameters:
    ///   - session: 待つセッション。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    /// - Returns: 完了の記録。
    /// - Throws: 期限内に記録されなければテスト失敗。
    func waitForCompletion(
        of session: ConnectionSession,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> RouteAnalysisTrackPortFake.Completion {
        await waitUntil("completion", file: file, line: line) { self.port.completions.contains { $0.sessionID == session.id } }
        return try XCTUnwrap(port.completions.last { $0.sessionID == session.id }, file: file, line: line)
    }
}

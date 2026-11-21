import Foundation
import XCTest
@testable import ProjectZD8

/// 解析の走行ルートの状態から地図の場所の内容を決める判定を検証します。
@MainActor
final class RouteAnalysisSectionContentPolicyTests: XCTestCase {
    /// 空の地図の内容です。
    private let layers = RouteAnalysisMapLayers(
        lines: [], markers: [], bounds: nil, legend: [], hasNoValueEdges: false, hasMatchedValues: true
    )

    /// 段階だけを指定した状態の内容を返します。
    ///
    /// 責務: 段階を持つ状態を作り、判定を通した結果を返します。
    private func content(phase: RouteAnalysisLoadPhase, layers: RouteAnalysisMapLayers? = nil) -> RouteAnalysisSectionContent {
        var state = RouteAnalysisState()
        state.phase = phase
        state.layers = layers
        return RouteAnalysisSectionContentPolicy().content(for: state)
    }

    /// 表示前は、通信中ではない読み込み中です。
    ///
    /// 責務: `idle` の結果を確認します。
    func testIdleIsLoadingWithoutRequest() {
        XCTAssertEqual(content(phase: .idle), .loading(isLoadingRoute: false))
    }

    /// サインイン待ちは、通信中ではない読み込み中です。
    ///
    /// 責務: `waitingForAccount` の結果を確認します。
    func testWaitingForAccountIsLoadingWithoutRequest() {
        XCTAssertEqual(content(phase: .waitingForAccount), .loading(isLoadingRoute: false))
    }

    /// 読み込み中は、通信中の読み込み中です。
    ///
    /// 責務: `loading` の結果を確認します。
    func testLoadingIsLoadingWithRequest() {
        XCTAssertEqual(content(phase: .loading), .loading(isLoadingRoute: true))
    }

    /// 準備できて地図の内容があれば、その内容を返します。
    ///
    /// 責務: `ready` と `layers` ありの結果を確認します。
    func testReadyWithLayersReturnsLayers() {
        XCTAssertEqual(content(phase: .ready, layers: layers), .ready(layers))
    }

    /// 準備できても地図の内容が無ければ、通信中ではない読み込み中です。
    ///
    /// 責務: `ready` と `layers` が nil の結果を確認します。
    func testReadyWithoutLayersIsLoadingWithoutRequest() {
        XCTAssertEqual(content(phase: .ready, layers: nil), .loading(isLoadingRoute: false))
    }

    /// 描けない理由と記号は、そのまま写されます。
    ///
    /// 責務: `unavailable` の値の写しを確認します。
    func testUnavailableCopiesReasonAndSymbol() {
        let result = content(phase: .unavailable(reasonKey: "reason.key", systemImage: "map"), layers: layers)
        XCTAssertEqual(result, .unavailable(reasonKey: "reason.key", systemImage: "map"))
    }

    /// 失敗のメッセージと再試行の可否は、そのまま写されます。
    ///
    /// 責務: `failed` の両方の再試行の値を確認します。
    func testFailedCopiesMessageAndRetryability() {
        XCTAssertEqual(
            content(phase: .failed(messageKey: "failure.key", isRetryable: true)),
            .failed(messageKey: "failure.key", isRetryable: true)
        )
        XCTAssertEqual(
            content(phase: .failed(messageKey: "failure.key", isRetryable: false), layers: layers),
            .failed(messageKey: "failure.key", isRetryable: false)
        )
    }
}

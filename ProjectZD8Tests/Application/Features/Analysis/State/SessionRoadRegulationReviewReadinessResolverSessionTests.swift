import Foundation
import XCTest
@testable import ProjectZD8

/// ルートと解析の状態が表示中のセッションのものかを照らして、照合の準備の段階を決める規則を検証します
/// (`readiness(for:routeSessionID:routePhase:analysisSessionID:analysisPhase:)`。管理役の確定仕様)。
///
/// 規則は上から: ルートの ID が違えば waitingForRoute、一致すれば従来の表、その結果が ready で解析の ID が違えば waitingForRawLog。
@MainActor
final class SessionRoadRegulationReviewReadinessResolverSessionTests: XCTestCase {
    /// 検証対象です。
    private let resolver = SessionRoadRegulationReviewReadinessResolver()
    /// 表示中のセッションです。
    private let shown = ConnectionSessionID()
    /// 別のセッションです。
    private let other = ConnectionSessionID()
    /// ルートの段階の6種類です(unavailable・failed は引数の値を変えて2つずつ含め、計8値)。
    private let routePhases: [RouteAnalysisLoadPhase] = [
        .idle, .waitingForAccount, .loading, .ready,
        .unavailable(reasonKey: "a", systemImage: "x"), .unavailable(reasonKey: "b", systemImage: "y"),
        .failed(messageKey: "m", isRetryable: true), .failed(messageKey: "n", isRetryable: false)
    ]
    /// 解析の段階の6値です。
    private let analysisPhases: [SessionLogAnalysisState.Phase] = [
        .idle, .awaitingDownloadConfirmation, .downloading, .loading, .loaded, .failed
    ]

    /// 表示中と違う ID の候補(別のセッションと nil)を返します。
    ///
    /// 責務: 「違う(nil を含む)」の2通りを並べます。
    /// - Returns: 違う ID。
    private func mismatchedIDs() -> [ConnectionSessionID?] {
        [other, nil]
    }

    /// ルートと解析の段階のすべての組み合わせを返します。
    ///
    /// 責務: 入れ子のループを1段にするため、段階の組を平らに並べます。
    /// - Returns: (ルートの段階, 解析の段階) の組。
    private func phasePairs() -> [(RouteAnalysisLoadPhase, SessionLogAnalysisState.Phase)] {
        routePhases.flatMap { route in analysisPhases.map { (route, $0) } }
    }

    /// 新しいメソッドを呼びます。
    ///
    /// 責務: 表示中のセッションを固定して、ID と段階から結果を返します。
    /// - Parameters:
    ///   - routeID: ルートの状態のセッション ID。
    ///   - route: ルートの段階。
    ///   - analysisID: 解析の状態のセッション ID。
    ///   - analysis: 解析の段階。
    /// - Returns: 照合の準備の段階。
    private func resolve(
        _ routeID: ConnectionSessionID?,
        _ route: RouteAnalysisLoadPhase,
        _ analysisID: ConnectionSessionID?,
        _ analysis: SessionLogAnalysisState.Phase
    ) -> SessionRoadRegulationReviewReadiness {
        resolver.readiness(for: shown, routeSessionID: routeID, routePhase: route, analysisSessionID: analysisID, analysisPhase: analysis)
    }

    /// 責務: ルートの ID が違う(別のセッション・nil)時は、段階と解析の ID に関係なく waitingForRoute であることを、全組み合わせで確かめます。
    func testMismatchedRouteSessionWaitsForRoute() {
        let analysisIDs: [ConnectionSessionID?] = [shown, other, nil]
        for routeID in mismatchedIDs() {
            for (route, analysis) in phasePairs() {
                let results = analysisIDs.map { resolve(routeID, route, $0, analysis) }

                XCTAssertEqual(results, [.waitingForRoute, .waitingForRoute, .waitingForRoute], "\(String(describing: routeID)) \(route) \(analysis)")
            }
        }
    }

    /// 責務: ルートが ready で解析の ID が違う(別のセッション・nil)時は、解析の段階に関係なく waitingForRawLog であることを確かめます。
    func testReadyRouteWithMismatchedAnalysisSessionWaitsForRawLog() {
        for analysisID in mismatchedIDs() {
            let results = analysisPhases.map { resolve(shown, .ready, analysisID, $0) }

            XCTAssertEqual(results, Array(repeating: .waitingForRawLog, count: 6), "\(String(describing: analysisID))")
        }
    }

    /// 責務: ルートの ID が一致し ready でない時は、解析の ID が違っても waitingForRoute / routeUnavailable のままであることを確かめます。
    func testNotReadyRouteIgnoresAnalysisSession() {
        let expected: [SessionRoadRegulationReviewReadiness] = [
            .waitingForRoute, .waitingForRoute, .waitingForRoute,
            .routeUnavailable, .routeUnavailable, .routeUnavailable, .routeUnavailable
        ]
        let notReady: [RouteAnalysisLoadPhase] = routePhases.filter { $0 != .ready }
        for analysisID in mismatchedIDs() {
            for analysis in analysisPhases {
                let results = notReady.map { resolve(shown, $0, analysisID, analysis) }

                XCTAssertEqual(results, expected, "\(String(describing: analysisID)) \(analysis)")
            }
        }
    }

    /// 責務: 両方の ID が一致する時、ルートが ready なら解析の段階ごとに従来の表(手で書いた値)どおりであることを確かめます。
    func testMatchedSessionsWithReadyRouteFollowTable() {
        let expected: [SessionRoadRegulationReviewReadiness] = [
            .waitingForRawLog, .ready(.inCloud), .waitingForRawLog, .waitingForRawLog, .ready(.onDevice), .ready(.unreadable)
        ]

        XCTAssertEqual(analysisPhases.map { resolve(shown, .ready, shown, $0) }, expected)
    }

    /// 責務: 両方の ID が一致する時は、全組み合わせで従来のメソッドと同じ結果であることを確かめます。
    func testMatchedSessionsEqualLegacyTable() {
        for (route, analysis) in phasePairs() {
            let legacy = resolver.readiness(routePhase: route, analysisPhase: analysis)

            XCTAssertEqual(resolve(shown, route, shown, analysis), legacy, "\(route) \(analysis)")
        }
    }
}

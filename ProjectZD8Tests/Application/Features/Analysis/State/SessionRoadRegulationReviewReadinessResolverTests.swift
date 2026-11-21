import Foundation
import XCTest
@testable import ProjectZD8

/// ルートの段階と解析の段階から、照合を始められるかを決める表を検証します(設計書 §3.4 Readiness、§7 TC1b)。
///
/// 6つのルートの段階 × 6つの解析の段階の36通りをすべて確かめます。
@MainActor
final class SessionRoadRegulationReviewReadinessResolverTests: XCTestCase {
    /// 検証対象です。
    private let resolver = SessionRoadRegulationReviewReadinessResolver()
    /// 解析の段階の6値です。
    private let analysisPhases: [SessionLogAnalysisState.Phase] = [
        .idle, .awaitingDownloadConfirmation, .downloading, .loading, .loaded, .failed
    ]

    /// ルートの段階1つについて、解析の6段階の結果を返します。
    ///
    /// 責務: 解析の段階の並びどおりに結果を並べます。
    /// - Parameter routePhase: ルートの段階。
    /// - Returns: 解析の段階ごとの結果。
    private func results(_ routePhase: RouteAnalysisLoadPhase) -> [SessionRoadRegulationReviewReadiness] {
        analysisPhases.map { resolver.readiness(routePhase: routePhase, analysisPhase: $0) }
    }

    /// 責務: ルートが idle・waitingForAccount・loading の時は、解析の段階に関係なく waitingForRoute であることを確かめます。
    func testRouteNotReadyWaitsForRoute() {
        let expected = Array(repeating: SessionRoadRegulationReviewReadiness.waitingForRoute, count: 6)

        for phase: RouteAnalysisLoadPhase in [.idle, .waitingForAccount, .loading] {
            XCTAssertEqual(results(phase), expected, "\(phase)")
        }
    }

    /// 責務: ルートが unavailable・failed の時は、引数の値を変えても解析の段階に関係なく routeUnavailable であることを確かめます。
    func testRouteUnavailableOrFailed() {
        let expected = Array(repeating: SessionRoadRegulationReviewReadiness.routeUnavailable, count: 6)
        let phases: [RouteAnalysisLoadPhase] = [
            .unavailable(reasonKey: "a", systemImage: "x"),
            .unavailable(reasonKey: "b", systemImage: "y"),
            .failed(messageKey: "m", isRetryable: true),
            .failed(messageKey: "n", isRetryable: false)
        ]

        for phase in phases {
            XCTAssertEqual(results(phase), expected, "\(phase)")
        }
    }

    /// 責務: ルートが ready の時、解析が idle・downloading・loading なら waitingForRawLog、確認待ちは ready(.inCloud)、
    /// loaded は ready(.onDevice)、failed は ready(.unreadable) であることを確かめます。
    func testRouteReadyDependsOnAnalysisPhase() {
        let expected: [SessionRoadRegulationReviewReadiness] = [
            .waitingForRawLog, .ready(.inCloud), .waitingForRawLog, .waitingForRawLog, .ready(.onDevice), .ready(.unreadable)
        ]

        XCTAssertEqual(results(.ready), expected)
    }
}

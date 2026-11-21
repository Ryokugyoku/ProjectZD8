import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 交通規制の組み立てが、DB を開けない時に利用不能な代替へ差し替えて診断を1件だけ残し、失敗を潰さないことを検証します。
@MainActor
final class RoadRegulationAssemblyTests: XCTestCase {
    /// DB を開けない失敗を表すテスト用エラーです。
    private struct OpenFailure: Error {}

    // MARK: - makeSettingsModel

    /// DB を開けなくてもモデルを作れ、診断は `.roadRegulations` が1件だけ残ります。
    ///
    /// 責務: 版の保存先が1回の準備で作られ、失敗が診断へちょうど1件残ることを確認します。
    func testSettingsModelWithUnopenableDatabaseRecordsSingleRoadRegulationsDiagnostic() {
        let spy = ProductDatabasePreparationDiagnosticsSpy()

        _ = RoadRegulationAssembly.makeSettingsModel(
            database: unopenableDatabase(),
            repositoryFactory: ProductDatabaseRepositoryFactory(diagnostics: spy)
        )

        XCTAssertEqual(spy.entries.map(\.storage), [.roadRegulations])
        XCTAssertTrue(spy.entries.first?.error is OpenFailure)
    }

    /// DB を開けない時に `appeared` を送ると、失敗が画面の状態へ失敗として表れ、空の一覧や成功にはなりません。
    ///
    /// 責務: 利用不能な代替の失敗が `storageUnavailable` として出て、版が1件も出ないことを確認します。
    func testSettingsModelAppearedSurfacesFailureInsteadOfEmptySuccess() async {
        let spy = ProductDatabasePreparationDiagnosticsSpy()
        let model = RoadRegulationAssembly.makeSettingsModel(
            database: unopenableDatabase(),
            repositoryFactory: ProductDatabaseRepositoryFactory(diagnostics: spy)
        )

        model.send(.appeared)

        let surfaced = await LocationRecordingBoundedWaiter.waitUntil("失敗が画面の状態に出る") {
            model.state.presentedError == .storageUnavailable
        }
        XCTAssertTrue(surfaced)
        XCTAssertEqual(model.state.presentedError, .storageUnavailable)
        XCTAssertTrue(model.state.rows.allSatisfy { $0.dataset == nil }, "失敗が空の一覧(版なし)に見えている")
        XCTAssertEqual(spy.entries.map(\.storage), [.roadRegulations], "画面を開いても診断は増えない")
    }

    /// DB を開ける時は診断が残らず、`appeared` で失敗は出ません。
    ///
    /// 責務: 成功時に利用不能へ差し替えず、診断を記録しないことを確認します。
    func testSettingsModelWithOpenableDatabaseRecordsNoDiagnosticsAndShowsNoError() async throws {
        let queue = try DatabaseQueue()
        let spy = ProductDatabasePreparationDiagnosticsSpy()
        let model = RoadRegulationAssembly.makeSettingsModel(
            database: ApplicationDatabaseConnection(openDatabaseQueue: { queue }),
            repositoryFactory: ProductDatabaseRepositoryFactory(diagnostics: spy)
        )

        model.send(.appeared)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(spy.entries.isEmpty)
        XCTAssertNil(model.state.presentedError)
    }

    // MARK: - makeEvaluation

    /// DB を開けない時、診断は `.roadRegulations` が1件だけで、版と検索で2件にはなりません。
    ///
    /// 責務: 版と検索を1回の準備でまとめて作ることを診断の件数で確認します。
    func testEvaluationWithUnopenableDatabaseRecordsSingleRoadRegulationsDiagnostic() {
        let spy = ProductDatabasePreparationDiagnosticsSpy()
        let harness = RoadRegulationEvaluationUseCaseHarness()

        _ = RoadRegulationAssembly.makeEvaluation(
            database: unopenableDatabase(),
            locations: harness.locations,
            rawLogs: harness.rawLogs,
            repositoryFactory: ProductDatabaseRepositoryFactory(diagnostics: spy)
        )

        XCTAssertEqual(spy.entries.map(\.storage), [.roadRegulations])
    }

    /// DB を開けない時に位置のあるセッションを評価すると、空の結果ではなく失敗が投げられます。
    ///
    /// 責務: 利用不能な版の保存先の失敗が、判定なし・規制データなしへ潰されないことを確認します。
    func testEvaluationWithUnopenableDatabaseThrowsInsteadOfEmptyOutcome() async throws {
        let harness = RoadRegulationEvaluationUseCaseHarness()
        try harness.seedTrack(count: 3)
        harness.seedRaw(count: 3)
        let useCase = RoadRegulationAssembly.makeEvaluation(
            database: unopenableDatabase(),
            locations: harness.locations,
            rawLogs: harness.rawLogs,
            repositoryFactory: ProductDatabaseRepositoryFactory(diagnostics: ProductDatabasePreparationDiagnosticsSpy())
        )
        let sessionID = harness.sessionID

        do {
            let outcome = try await useCase.execute(sessionID: sessionID)
            XCTFail("失敗が投げられず結果になった: \(outcome)")
        } catch {
            XCTAssertEqual(error as? RoadRegulationRepositoryError, .unavailable)
        }
    }

    /// DB を開ける時は診断が残らず、版が無ければ規制データなしの結果になります。
    ///
    /// 責務: 成功時に実 Repository が使われ、診断が0件であることを確認します。
    func testEvaluationWithOpenableDatabaseRecordsNoDiagnosticsAndReportsNoRegulationData() async throws {
        let queue = try DatabaseQueue()
        let spy = ProductDatabasePreparationDiagnosticsSpy()
        let harness = RoadRegulationEvaluationUseCaseHarness()
        try harness.seedTrack(count: 3)
        let useCase = RoadRegulationAssembly.makeEvaluation(
            database: ApplicationDatabaseConnection(openDatabaseQueue: { queue }),
            locations: harness.locations,
            rawLogs: harness.rawLogs,
            repositoryFactory: ProductDatabaseRepositoryFactory(diagnostics: spy)
        )
        let sessionID = harness.sessionID

        let outcome = try await useCase.execute(sessionID: sessionID)

        XCTAssertEqual(outcome, .noRegulationData)
        XCTAssertTrue(spy.entries.isEmpty)
    }

    // MARK: - ProductDatabaseStorageKind

    /// 保存先の種類の全 case に `.roadRegulations` が含まれます。
    ///
    /// 責務: 既存の全 case を回す検証(`ProductDatabaseRepositoryFactoryTests`)に新しい case が入ることを確認します。
    func testStorageKindAllCasesIncludeRoadRegulations() {
        XCTAssertTrue(ProductDatabaseStorageKind.allCases.contains(.roadRegulations))
    }

    // MARK: - Helpers

    /// 開く処理が失敗する製品DB接続を作ります。
    ///
    /// 責務: `OpenFailure` を投げる接続を返します。
    /// - Returns: 開けなかった製品DB接続。
    private func unopenableDatabase() -> ApplicationDatabaseConnection {
        ApplicationDatabaseConnection(openDatabaseQueue: { throw OpenFailure() })
    }
}

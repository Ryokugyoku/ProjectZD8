import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 交通規制の照合のモデルの組み立てを検証します(設計書 §3.6「Composition」・§7 TC4・§9-11)。
///
/// DB を開けない時: モデルは作れ、評価は空の結果でなく `failed` になります。診断は、位置の保存先が1件、交通規制が
/// 判定(版と検索を1回の準備)の1件と版の一覧の1件で計2件残ります(§9-11 の「診断の重複」)。
/// DB を開ける時(メモリ内): 診断は0件で、位置の無いセッションは `noTrack` になります。待ちは期限つき(2秒)です。
@MainActor
final class SessionRoadRegulationReviewCompositionTests: XCTestCase {
    /// DB を開けない失敗を表すテスト用エラーです。
    private struct OpenFailure: Error {}

    /// 準備の失敗の記録です。
    private let spy = ProductDatabasePreparationDiagnosticsSpy()

    /// 責務: 診断の記録つきの保存先の工場でモデルを作ります。
    /// - Parameter database: 製品DB接続。
    /// - Returns: モデル。
    private func makeModel(database: ApplicationDatabaseConnection) -> SessionRoadRegulationReviewModel {
        SessionRoadRegulationReviewComposition.makeModel(
            database: database,
            rawLogs: RoadRegulationRawLogRepositoryFake(),
            repositoryFactory: ProductDatabaseRepositoryFactory(diagnostics: spy)
        )
    }

    /// 責務: 開く処理が失敗する製品DB接続を返します。
    private func unopenableDatabase() -> ApplicationDatabaseConnection {
        ApplicationDatabaseConnection(openDatabaseQueue: { throw OpenFailure() })
    }

    /// 責務: 診断を保存先の種類ごとの件数にして返します(並びは問わない)。
    private var diagnosticCounts: [ProductDatabaseStorageKind: Int] {
        spy.entries.reduce(into: [:]) { $0[$1.storage, default: 0] += 1 }
    }

    /// 責務: ready(.onDevice) を送り、status が指定の値になるまで期限つきで待ちます。
    private func evaluate(_ model: SessionRoadRegulationReviewModel, until status: SessionRoadRegulationReviewStatus) async {
        model.send(.readinessChanged(ConnectionSessionID(), .ready(.onDevice)))
        await LocationRecordingBoundedWaiter.waitUntil("status \(status)") { model.state.status == status }
    }

    /// 責務: DB を開けなくてもモデルを作れ、初期の状態(idle)であることを確かめます。
    func testUnopenableDatabaseStillMakesIdleModel() {
        let model = makeModel(database: unopenableDatabase())

        XCTAssertEqual(model.state, SessionRoadRegulationReviewState())
    }

    /// 責務: DB を開けない時の診断が、位置1件・交通規制2件で、失敗の原因を持つことを確かめます。
    func testUnopenableDatabaseRecordsExpectedDiagnostics() {
        _ = makeModel(database: unopenableDatabase())

        XCTAssertEqual(diagnosticCounts, [.connectionSessionLocations: 1, .roadRegulations: 2])
        XCTAssertTrue(spy.entries.allSatisfy { $0.error is OpenFailure })
    }

    /// 責務: DB を開けない時の評価は、空の結果(noTrack・noRegulationData・空の loaded)でなく failed になり、診断は増えないことを確かめます。
    func testUnopenableDatabaseEvaluationFails() async {
        let model = makeModel(database: unopenableDatabase())
        let countsBefore = diagnosticCounts

        await evaluate(model, until: .failed)

        XCTAssertEqual(model.state.status, .failed)
        XCTAssertEqual(model.state.summaries, [])
        XCTAssertEqual(model.state.overlays, [])
        XCTAssertEqual(diagnosticCounts, countsBefore)
    }

    /// 責務: DB を開ける時(メモリ内)は診断が0件で、モデルは idle であることを確かめます。
    func testOpenableDatabaseRecordsNoDiagnostics() throws {
        let queue = try DatabaseQueue()

        let model = makeModel(database: ApplicationDatabaseConnection(openDatabaseQueue: { queue }))

        XCTAssertTrue(spy.entries.isEmpty)
        XCTAssertEqual(model.state, SessionRoadRegulationReviewState())
    }

    /// 責務: DB を開ける時、位置の無いセッションの評価は noTrack になり、内容が空で診断も0件のままであることを確かめます。
    func testOpenableDatabaseSessionWithoutTrackIsNoTrack() async throws {
        let queue = try DatabaseQueue()
        let model = makeModel(database: ApplicationDatabaseConnection(openDatabaseQueue: { queue }))

        await evaluate(model, until: .noTrack)

        XCTAssertEqual(model.state.status, .noTrack)
        XCTAssertEqual(model.state.sections, [])
        XCTAssertEqual(model.state.attribution, .empty)
        XCTAssertTrue(spy.entries.isEmpty)
    }

    /// 責務: 保存先の工場を省いても(既定の nil)モデルを作れることを確かめます。
    func testDefaultRepositoryFactoryMakesIdleModel() throws {
        let queue = try DatabaseQueue()

        let model = SessionRoadRegulationReviewComposition.makeModel(
            database: ApplicationDatabaseConnection(openDatabaseQueue: { queue }), rawLogs: RoadRegulationRawLogRepositoryFake()
        )

        XCTAssertEqual(model.state, SessionRoadRegulationReviewState())
    }
}

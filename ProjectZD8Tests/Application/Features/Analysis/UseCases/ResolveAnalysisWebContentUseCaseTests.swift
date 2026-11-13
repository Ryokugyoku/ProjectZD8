import XCTest
@testable import ProjectZD8

/// ワークベンチの配信パス解決を検証します。
final class ResolveAnalysisWebContentUseCaseTests: XCTestCase {
    /// 責務: 一時ディレクトリへ同梱ファイル相当を置いたユースケースを作ります。
    private func makeSUT() throws -> (ResolveAnalysisWebContentUseCase, AnalysisDatasetStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("<html></html>".utf8).write(to: directory.appendingPathComponent("analysis-index.html"))
        try Data("export {}".utf8).write(to: directory.appendingPathComponent("analysis-app.js"))
        try Data("secret".utf8).write(to: directory.appendingPathComponent("notes.txt"))
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = AnalysisDatasetStore()
        return (ResolveAnalysisWebContentUseCase(resourceDirectory: directory, store: store), store)
    }

    /// 責務: 入口・スクリプト・保存済みデータを返し、許可外は拒否することを確認します。
    func testResolvesAllowedPathsOnly() throws {
        let (useCase, store) = try makeSUT()
        let id = SessionID()
        store.set(Data("{}".utf8), forPath: AnalysisDatasetStore.datasetPath(for: id))

        XCTAssertEqual(useCase.content(for: ResolveAnalysisWebContentUseCase.indexURL)?.mimeType, "text/html")
        XCTAssertEqual(useCase.content(for: URL(string: "rtanalysis://app/")!)?.mimeType, "text/html")
        XCTAssertEqual(useCase.content(for: URL(string: "rtanalysis://app/analysis-app.js")!)?.mimeType, "text/javascript")
        XCTAssertEqual(useCase.content(for: URL(string: "rtanalysis://app/dataset/\(id.rawValue.uuidString).json")!)?.data, Data("{}".utf8))

        XCTAssertNil(useCase.content(for: URL(string: "rtanalysis://app/notes.txt")!), "許可外の拡張子")
        XCTAssertNil(useCase.content(for: URL(string: "rtanalysis://app/missing.js")!))
        XCTAssertNil(useCase.content(for: URL(string: "rtanalysis://app/dataset/unknown.json")!))
        XCTAssertNil(useCase.content(for: URL(string: "rtanalysis://app/../analysis-app.js")!))
        XCTAssertNil(useCase.content(for: URL(string: "rtanalysis://app/dataset/..%2Fx.json")!))
        XCTAssertNil(useCase.content(for: URL(string: "https://app/analysis-app.js")!))
        XCTAssertNil(useCase.content(for: URL(string: "rtanalysis://evil/analysis-app.js")!))
        XCTAssertNil(useCase.content(for: URL(string: "file:///etc/passwd")!))
    }
}

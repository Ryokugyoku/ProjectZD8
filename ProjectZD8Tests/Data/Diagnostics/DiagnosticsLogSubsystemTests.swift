import Foundation
import XCTest

/// 製品ソース(アプリと Widget Extension)の統合ログの生成箇所が、すべて共通の subsystem(`DiagnosticsLogSubsystem.identifier`)と決まった category を使うことを検証します。
final class DiagnosticsLogSubsystemTests: XCTestCase {
    /// 共通の subsystem の式です。
    private static let sharedSubsystem = "DiagnosticsLogSubsystem.identifier"
    /// 走査する製品ソースのディレクトリです(アプリと Live Activity の Widget Extension)。
    private static let productDirectories = ["ProjectZD8", "RecordingSessionLiveActivity"]
    /// 共通の subsystem を定義するファイルです。
    private static let definitionPath = "ProjectZD8/Data/Diagnostics/DiagnosticsLogSubsystem.swift"
    /// 製品ソースで使ってよい category の集合です(signpost は変更前の値 `AcquisitionPerformance`)。
    private static let expectedCategories: Set<String> = [
        "AppleCoreBluetoothOBDTransport", "ConnectionSessionPersistence", "AcquisitionEvidencePersistence",
        "AcquisitionChunkPersistence", "OBDSerialTransport", "OBDBluetoothRFCOMMTransport", "BLELink",
        "VehicleDetectionNotification", "VehicleRecording", "RecordingSessionActivity", "PostSessionProcessing",
        "Acquisition", "LiveActivity", "AcquisitionPerformance"
    ]

    /// すべての生成箇所が、共通の subsystem を渡しています(1件以上あること)。
    ///
    /// 責務: 複数行の引数を含む各生成箇所の subsystem を確認します。
    func testEveryCreationSiteUsesSharedSubsystem() throws {
        let scanner = try DiagnosticsLogSourceScanner()
        let sites = try Self.productDirectories.flatMap { try scanner.creationSites(under: $0) }

        XCTAssertFalse(sites.isEmpty, "生成箇所が見つかりません(走査の不具合)")
        for site in sites {
            XCTAssertEqual(site.subsystem, Self.sharedSubsystem, "\(site.path):\(site.line) \(site.arguments)")
        }
    }

    /// 定義ファイル以外で、`subsystem:` に共通の式以外(文字列リテラルや `Bundle.main.bundleIdentifier`)を渡していません。
    ///
    /// 責務: 生成箇所の検出に漏れがあっても、`subsystem:` の全出現を直接確認します。
    func testNoOtherSubsystemExpressionOutsideDefinition() throws {
        let scanner = try DiagnosticsLogSourceScanner()
        let regex = try NSRegularExpression(pattern: #"subsystem:\s*([^,\)\n]+)"#)
        var occurrences = 0
        let sources = try Self.productDirectories.flatMap { try scanner.swiftSources(under: $0) }
        XCTAssertTrue(sources.contains { $0.path.hasPrefix("RecordingSessionLiveActivity/") }, "Extension のソースを走査していません")
        for source in sources where source.path != Self.definitionPath {
            let code = DiagnosticsLogSourceScanner.removingCommentLines(source.text)
            for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                occurrences += 1
                let value = Range(match.range(at: 1), in: code).map { code[$0].trimmingCharacters(in: .whitespaces) }
                XCTAssertEqual(value, Self.sharedSubsystem, source.path)
            }
        }
        XCTAssertGreaterThan(occurrences, 0, "subsystem: が1件も見つかりません(走査の不具合)")
    }

    /// 生成箇所の category の集合が、決まった集合と一致します(増減があれば失敗)。
    ///
    /// 責務: 各生成箇所が category を持ち、その集合が期待どおりであることを確認します。
    func testCategoriesMatchExpectedSet() throws {
        let scanner = try DiagnosticsLogSourceScanner()
        let sites = try Self.productDirectories.flatMap { try scanner.creationSites(under: $0) }

        XCTAssertFalse(sites.isEmpty, "生成箇所が見つかりません(走査の不具合)")
        for site in sites {
            XCTAssertNotNil(site.category, "\(site.path):\(site.line) に category がありません")
        }
        XCTAssertEqual(Set(sites.compactMap(\.category)), Self.expectedCategories)
    }

    /// Application 層と Domain 層の Swift ソースは `OSLog` と `os` を import しません。
    ///
    /// 責務: 層の規則どおり、統合ログへの依存が Data 層にだけあることを確認します。
    func testApplicationAndDomainDoNotImportOSLog() throws {
        let scanner = try DiagnosticsLogSourceScanner()
        let regex = try NSRegularExpression(pattern: #"^\s*import\s+(OSLog|os)\b"#, options: [.anchorsMatchLines])
        var fileCount = 0
        for directory in ["ProjectZD8/Application", "ProjectZD8/Domain"] {
            for source in try scanner.swiftSources(under: directory) {
                fileCount += 1
                let range = NSRange(source.text.startIndex..., in: source.text)
                XCTAssertNil(regex.firstMatch(in: source.text, range: range), source.path)
            }
        }
        XCTAssertGreaterThan(fileCount, 0, "Application・Domain のソースが見つかりません(走査の不具合)")
    }
}

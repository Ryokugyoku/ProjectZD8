import Foundation
import XCTest

/// アプリの `Info.plist` に、セッション外の後処理(`BGProcessingTask`)の宣言があり、既存のバックグラウンドモードが残っていることを検証します。
final class InfoPlistTests: XCTestCase {
    /// `UIBackgroundModes` に `processing` があり、既存の `bluetooth-central` と `external-accessory` が残っています。
    ///
    /// 責務: バックグラウンドモードの宣言を確認します。
    func testBackgroundModesIncludeProcessingAndKeepExistingModes() throws {
        let modes = try XCTUnwrap(try loadInfoPlist()["UIBackgroundModes"] as? [String])

        XCTAssertTrue(modes.contains("processing"), "\(modes)")
        XCTAssertTrue(modes.contains("bluetooth-central"), "\(modes)")
        XCTAssertTrue(modes.contains("external-accessory"), "\(modes)")
    }

    /// `BGTaskSchedulerPermittedIdentifiers` に、`.post-session-processing` で終わる識別子が1件あります。
    ///
    /// 責務: 後処理のタスク識別子の許可を確認します。
    func testPermittedIdentifiersContainOnePostSessionProcessingIdentifier() throws {
        let identifiers = try XCTUnwrap(try loadInfoPlist()["BGTaskSchedulerPermittedIdentifiers"] as? [String])

        XCTAssertEqual(identifiers.filter { $0.hasSuffix(".post-session-processing") }.count, 1, "\(identifiers)")
    }

    /// リポジトリの `ProjectZD8/Info.plist` を読みます。
    ///
    /// 責務: テストファイル位置からリポジトリルートを解決し、plist を辞書へ変換します。
    /// - Returns: plist の最上位の辞書。
    /// - Throws: パス解決・読込・変換の失敗。
    private func loadInfoPlist() throws -> [String: Any] {
        let components = URL(filePath: #filePath).pathComponents
        guard let testsIndex = components.firstIndex(of: "ProjectZD8Tests") else {
            throw InfoPlistTestError.repositoryRootNotFound
        }
        let root = URL(filePath: NSString.path(withComponents: Array(components[..<testsIndex])))
        let data = try Data(contentsOf: root.appending(path: "ProjectZD8/Info.plist"))
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw InfoPlistTestError.notDictionary
        }
        return plist
    }
}

/// `Info.plist` テストの読込エラーです。
private enum InfoPlistTestError: Error {
    /// テストファイル位置からリポジトリルートを特定できませんでした。
    case repositoryRootNotFound
    /// plist の最上位が辞書ではありませんでした。
    case notDictionary
}

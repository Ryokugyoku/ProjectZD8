import Foundation
import XCTest

/// アプリの `Info.plist` に、位置情報の記録に必要な宣言があることを検証します。
final class InfoPlistLocationTests: XCTestCase {
    /// `UIBackgroundModes` に `location` があり、既存のモードが残っています。
    ///
    /// 責務: 位置情報のバックグラウンドモードと既存モードの共存を確認します。
    func testBackgroundModesIncludeLocationAndKeepExistingModes() throws {
        let modes = try XCTUnwrap(try loadInfoPlist()["UIBackgroundModes"] as? [String])

        XCTAssertTrue(modes.contains("location"), "\(modes)")
        XCTAssertTrue(modes.contains("bluetooth-central"), "\(modes)")
        XCTAssertTrue(modes.contains("external-accessory"), "\(modes)")
        XCTAssertTrue(modes.contains("processing"), "\(modes)")
    }

    /// 位置情報の用途説明が2つとも存在し、空ではありません。
    ///
    /// 責務: 「使用中」と「常に」の用途説明キーを確認します。
    func testLocationUsageDescriptionsArePresentAndNonEmpty() throws {
        let plist = try loadInfoPlist()
        for key in ["NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription"] {
            let value = try XCTUnwrap(plist[key] as? String, "キーが無いか文字列でない: \(key)")
            XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key)
        }
    }

    /// リポジトリの `ProjectZD8/Info.plist` を読みます。
    ///
    /// 責務: テストファイル位置からリポジトリルートを解決し、plist を辞書へ変換します。
    private func loadInfoPlist() throws -> [String: Any] {
        let components = URL(filePath: #filePath).pathComponents
        guard let testsIndex = components.firstIndex(of: "ProjectZD8Tests") else {
            throw InfoPlistLocationTestError.repositoryRootNotFound
        }
        let root = URL(filePath: NSString.path(withComponents: Array(components[..<testsIndex])))
        let data = try Data(contentsOf: root.appending(path: "ProjectZD8/Info.plist"))
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw InfoPlistLocationTestError.notDictionary
        }
        return plist
    }
}

/// 位置情報の `Info.plist` テストの読込エラーです。
private enum InfoPlistLocationTestError: Error {
    /// テストファイル位置からリポジトリルートを特定できませんでした。
    case repositoryRootNotFound
    /// plist の最上位が辞書ではありませんでした。
    case notDictionary
}

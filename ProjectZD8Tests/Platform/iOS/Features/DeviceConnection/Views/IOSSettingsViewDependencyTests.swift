#if os(iOS)
import Foundation
import XCTest

/// iOS設定Viewのデバイス層依存境界を検証します。
final class IOSSettingsViewDependencyTests: XCTestCase {
    /// iOS設定View群がCoreBluetoothやData実装へ直接依存しないことを検証します。
    ///
    /// 責務: 変更対象のiOS設定Viewソースに禁止されたインフラ参照がないことを確認します。
    func testSettingsViewsDoNotReferenceCoreBluetoothOrDataAdapters() throws {
        let repositoryRoot = try repositoryRootURL()
        let viewURLs = [
            repositoryRoot.appending(path: "ProjectZD8/Platform/iOS/AppShell/IOSSettingsView.swift"),
            repositoryRoot.appending(path: "ProjectZD8/Platform/iOS/Features/DeviceConnection/Views/IOSAdapterSelectionView.swift"),
            repositoryRoot.appending(path: "ProjectZD8/Platform/iOS/Features/DeviceConnection/Views/IOSAdapterConnectionDetailView.swift")
        ]

        for viewURL in viewURLs {
            let source = try String(contentsOf: viewURL, encoding: .utf8)
            XCTAssertFalse(source.contains("import CoreBluetooth"), viewURL.path())
            XCTAssertFalse(source.contains("AppleCoreBluetoothAdapterDiscovery"), viewURL.path())
            XCTAssertFalse(source.contains("ProjectZD8/Data"), viewURL.path())
        }
    }

    /// 現在のテストファイル位置からリポジトリルートURLを解決します。
    ///
    /// 責務: ソース依存テストが参照するProjectZD8リポジトリルートを一意に返します。
    /// - Returns: `ProjectZD8Tests` の親ディレクトリURL。
    /// - Throws: テストファイルパスから `ProjectZD8Tests` を特定できない場合のエラー。
    private func repositoryRootURL() throws -> URL {
        let components = URL(filePath: #filePath).pathComponents
        guard let testsIndex = components.firstIndex(of: "ProjectZD8Tests") else {
            throw IOSSettingsViewDependencyTestError.repositoryRootNotFound
        }
        return URL(filePath: NSString.path(withComponents: Array(components[..<testsIndex])))
    }
}

/// iOS設定View依存テストのパス解決エラーです。
private enum IOSSettingsViewDependencyTestError: Error {
    /// テストファイル位置からリポジトリルートを特定できませんでした。
    case repositoryRootNotFound
}
#endif

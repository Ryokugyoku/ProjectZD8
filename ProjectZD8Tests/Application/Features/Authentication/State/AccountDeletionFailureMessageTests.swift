import Foundation
import XCTest
@testable import ProjectZD8

/// `AccountDeletionFailureMessage` が全ての原因に文言キーを返し、各キーが日本語・英語・スペイン語でそろっていることを検証します。
final class AccountDeletionFailureMessageTests: XCTestCase {
    /// 検証対象の言語です。
    private static let languages = ["ja", "en", "es"]

    /// 全ての原因を返します。新しい原因を足すとここがコンパイルエラーになり、検証漏れを防ぎます。
    ///
    /// 責務: `switch` の網羅性を使って、原因の全列挙を保証します。
    /// - Returns: 全ての原因。
    private static func allFailures() -> [AccountDeletionFailure] {
        let seeds: [AccountDeletionFailure] = [.iCloudUnavailable, .networkUnavailable, .serviceBusy, .acquisitionTimedOut, .deletionFailed]
        for failure in seeds {
            switch failure {
            case .iCloudUnavailable, .networkUnavailable, .serviceBusy, .acquisitionTimedOut, .deletionFailed: break
            }
        }
        return seeds
    }

    /// 原因ごとに期待する文言キーを返します。
    ///
    /// 責務: 仕様の対応表(原因 → キー)を1か所に持ちます。
    /// - Returns: 原因から期待するキーへの対応。
    private static func expectedKeys() -> [(AccountDeletionFailure, String)] {
        [
            (.iCloudUnavailable, "account.delete.error.icloud"),
            (.networkUnavailable, "account.delete.error.network"),
            (.serviceBusy, "account.delete.error.busy"),
            (.acquisitionTimedOut, "account.delete.error.acquisition_timeout"),
            (.deletionFailed, "account.delete.error")
        ]
    }

    /// 全ての原因が、期待するキーへ対応することを検証します。
    ///
    /// 責務: 原因ごとのキーと、キーが互いに異なることを確認します。
    func testEveryFailureMapsToItsKey() {
        XCTAssertEqual(Self.expectedKeys().count, Self.allFailures().count)
        for (failure, expected) in Self.expectedKeys() {
            XCTAssertEqual(AccountDeletionFailureMessage.key(for: failure), expected, "\(failure)")
        }
        let keys = Self.allFailures().map { AccountDeletionFailureMessage.key(for: $0) }
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    /// 全てのキーが、`Localizable.xcstrings` に日本語・英語・スペイン語の空でない値を持つことを検証します。
    ///
    /// 責務: 文字列カタログを JSON として読み、キーごとに3言語の値を確認します。
    func testEveryKeyHasNonEmptyValueInAllLanguages() throws {
        let strings = try Self.catalogStrings()
        for failure in Self.allFailures() {
            let key = AccountDeletionFailureMessage.key(for: failure)
            let entry = try XCTUnwrap(strings[key] as? [String: Any], "カタログにキーが無い: \(key)")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            for language in Self.languages {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = try XCTUnwrap(unit?["value"] as? String, "\(key) の \(language) が無い")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(key) \(language)")
            }
        }
    }

    /// 文字列カタログの `strings` を読みます。
    ///
    /// 責務: リポジトリの `Localizable.xcstrings` を JSON として読み込みます。
    /// - Returns: キーからエントリへの対応。
    private static func catalogStrings() throws -> [String: Any] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent("ProjectZD8/Resources/Localization/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap((object as? [String: Any])?["strings"] as? [String: Any])
    }
}

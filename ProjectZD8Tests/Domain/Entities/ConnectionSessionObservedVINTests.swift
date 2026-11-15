import Foundation
import XCTest
@testable import ProjectZD8

/// `ConnectionSession.observedVIN` の正規化と符号化互換性を、生成・代入・復号の各経路で検証します。
final class ConnectionSessionObservedVINTests: XCTestCase {
    /// 正規化済みの代表VINです。
    private static let vin = "JF1ZD8ABC12345678"

    // MARK: - init

    /// イニシャライザは前後の空白・タブ・改行を除いた値を保持します。
    ///
    /// 責務: 生成経路で前後の空白類が除去されることを確認します。
    func testInitTrimsLeadingAndTrailingWhitespaceAndNewlines() {
        let session = ConnectionSession(accountIdentifier: "account", observedVIN: " \t\n\(Self.vin)\r\n ")

        XCTAssertEqual(session.observedVIN, Self.vin)
    }

    /// イニシャライザへ空文字を渡すと `nil` になります。
    ///
    /// 責務: 生成経路の境界値(長さ0)が `nil` へ変換されることを確認します。
    func testInitStoresNilForEmptyString() {
        XCTAssertNil(ConnectionSession(accountIdentifier: "account", observedVIN: "").observedVIN)
    }

    /// イニシャライザへ空白類だけを渡すと `nil` になります。
    ///
    /// 責務: 生成経路で空白・タブ・改行だけの値が非空として残らないことを確認します。
    func testInitStoresNilForWhitespaceOnlyString() {
        XCTAssertNil(ConnectionSession(accountIdentifier: "account", observedVIN: " \t\n ").observedVIN)
    }

    /// イニシャライザで省略または `nil` を渡すと `nil` のままです。
    ///
    /// 責務: 既存の呼び出し形(引数省略)で観測VINが付かないことを確認します。
    func testInitDefaultsToNil() {
        XCTAssertNil(ConnectionSession(accountIdentifier: "account").observedVIN)
        XCTAssertNil(ConnectionSession(accountIdentifier: "account", observedVIN: nil).observedVIN)
    }

    /// イニシャライザは内側の空白と大文字小文字を変更しません。
    ///
    /// 責務: 正規化が前後の除去だけで、大文字化や内側空白の除去をしないことを確認します。
    func testInitPreservesInnerWhitespaceAndLetterCase() {
        let session = ConnectionSession(accountIdentifier: "account", observedVIN: "  jf1 Zd8abc  ")

        XCTAssertEqual(session.observedVIN, "jf1 Zd8abc")
    }

    // MARK: - assignment

    /// 代入値は前後の空白・改行を除いて保持されます。
    ///
    /// 責務: 代入経路でもイニシャライザと同じ前後除去が行われることを確認します。
    func testAssignmentTrimsLeadingAndTrailingWhitespace() {
        var session = ConnectionSession(accountIdentifier: "account")

        session.observedVIN = "\n \(Self.vin)\t"

        XCTAssertEqual(session.observedVIN, Self.vin)
    }

    /// 空白類だけを代入すると既存値が消えて `nil` になります。
    ///
    /// 責務: 代入経路で空白だけの値が非空として残らないことを確認します。
    func testAssignmentOfWhitespaceOnlyClearsToNil() {
        var session = ConnectionSession(accountIdentifier: "account", observedVIN: Self.vin)

        session.observedVIN = " \n\t "

        XCTAssertNil(session.observedVIN)
    }

    /// 空文字を代入すると `nil` になります。
    ///
    /// 責務: 代入経路の境界値(長さ0)が `nil` へ変換されることを確認します。
    func testAssignmentOfEmptyStringClearsToNil() {
        var session = ConnectionSession(accountIdentifier: "account", observedVIN: Self.vin)

        session.observedVIN = ""

        XCTAssertNil(session.observedVIN)
    }

    /// 代入は内側の空白と大文字小文字を変更しません。
    ///
    /// 責務: 代入経路でも内側空白と文字種が保たれることを確認します。
    func testAssignmentPreservesInnerWhitespaceAndLetterCase() {
        var session = ConnectionSession(accountIdentifier: "account")

        session.observedVIN = " aB c "

        XCTAssertEqual(session.observedVIN, "aB c")
    }

    // MARK: - normalizedObservedVIN(_:)

    /// 正規化関数は前後の空白類を除いた非空文字列か `nil` を返します。
    ///
    /// 責務: `nil`・空文字・空白だけ・前後空白付き・内側空白付きの各入力に対する戻り値を確認します。
    func testNormalizedObservedVINCoversNilEmptyWhitespaceAndTrimmedInputs() {
        XCTAssertNil(ConnectionSession.normalizedObservedVIN(nil))
        XCTAssertNil(ConnectionSession.normalizedObservedVIN(""))
        XCTAssertNil(ConnectionSession.normalizedObservedVIN(" \t\r\n"))
        XCTAssertEqual(ConnectionSession.normalizedObservedVIN(" \(Self.vin)\n"), Self.vin)
        XCTAssertEqual(ConnectionSession.normalizedObservedVIN("a b"), "a b")
        XCTAssertEqual(ConnectionSession.normalizedObservedVIN("x"), "x")
    }
}

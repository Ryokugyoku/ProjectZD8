import Foundation
import XCTest
@testable import ProjectZD8

/// 未登録車両の警告 `UnassignedObservedVINWarning` の表示可否・文言キー・引数・主要操作を検証します。
@MainActor
final class UnassignedObservedVINWarningTests: XCTestCase {
    /// 警告に使うセッションを作ります。
    private typealias Fixture = UnassignedObservedVINSessionFixture

    /// 指定VINを順に観測したセッションから警告を作ります。
    ///
    /// 責務: VIN配列を開始時刻が1秒ずつ新しくなるセッション列へ変換し、警告を生成します。
    /// - Parameter vins: 古い順の観測VIN。
    /// - Returns: 生成した警告。
    private func warning(vins: [String]) -> UnassignedObservedVINWarning {
        UnassignedObservedVINWarning(sessions: vins.enumerated().map { Fixture.session(vin: $1, startedAt: Double($0 + 1)) })
    }

    /// 0件では警告を出さず、文言・引数・操作もありません。
    ///
    /// 責務: 空の照会結果が `.hidden` になり、非表示時の各プロパティが空であることを確認します。
    func testEmptySessionsAreHidden() {
        let hidden = UnassignedObservedVINWarning(sessions: [])
        XCTAssertEqual(hidden, .hidden)
        XCTAssertFalse(hidden.isVisible)
        XCTAssertNil(hidden.titleKey)
        XCTAssertNil(hidden.messageKey)
        XCTAssertEqual(hidden.messageArguments, [])
        XCTAssertNil(hidden.systemImageName)
        XCTAssertNil(hidden.primaryAction)
    }

    /// 1件以上あれば警告を出し、見出し・本文・アイコンを持ちます。
    ///
    /// 責務: 1台1件・1台複数件・複数台のすべてで表示対象になることを確認します。
    func testAnySessionProducesVisibleWarning() {
        let cases = [[Fixture.firstVIN], [Fixture.firstVIN, Fixture.firstVIN], [Fixture.firstVIN, Fixture.secondVIN]]
        for vins in cases {
            let item = warning(vins: vins)
            XCTAssertTrue(item.isVisible, "\(vins)")
            XCTAssertNotNil(item.titleKey, "\(vins)")
            XCTAssertNotNil(item.messageKey, "\(vins)")
            XCTAssertNotNil(item.systemImageName, "\(vins)")
        }
    }

    /// 本文の引数は車両数とログ件数の両方です。
    ///
    /// 責務: 1台1件・1台複数件・大文字小文字違いを含む複数台の境界で `[車両数, 件数]` が渡ることを確認します。
    func testMessageArgumentsAreVehicleCountAndLogCount() {
        XCTAssertEqual(warning(vins: [Fixture.firstVIN]).messageArguments, [1, 1])
        XCTAssertEqual(warning(vins: [Fixture.firstVIN, Fixture.firstVIN.lowercased(), Fixture.firstVIN]).messageArguments, [1, 3])
        let many = [Fixture.firstVIN, Fixture.secondVIN, Fixture.thirdVIN, Fixture.secondVIN]
        XCTAssertEqual(warning(vins: many).messageArguments, [3, 4])
    }

    /// 1台1件・1台複数件・複数台のどれでも本文キーは失敗時の本文キーと別です。
    ///
    /// 責務: 件数による本文キーの選択が、照会失敗の文言と取り違えられていないことを確認します。
    func testUnregisteredMessageKeysDifferFromFailureMessageKey() {
        let failureKey = UnassignedObservedVINWarning.loadFailed.messageKey
        for vins in [[Fixture.firstVIN], [Fixture.firstVIN, Fixture.firstVIN], [Fixture.firstVIN, Fixture.secondVIN]] {
            XCTAssertNotEqual(warning(vins: vins).messageKey, failureKey, "\(vins)")
        }
    }

    /// 照会失敗は非表示とは別の、表示対象の状態です。
    ///
    /// 責務: `.loadFailed` が表示され、見出し・本文が未登録警告と別で、引数を持たないことを確認します。
    func testLoadFailedIsVisibleAndDistinct() {
        let failed = UnassignedObservedVINWarning.loadFailed
        let unregistered = warning(vins: [Fixture.firstVIN])
        XCTAssertNotEqual(failed, .hidden)
        XCTAssertTrue(failed.isVisible)
        XCTAssertNotNil(failed.titleKey)
        XCTAssertNotNil(failed.messageKey)
        XCTAssertNotEqual(failed.titleKey, unregistered.titleKey)
        XCTAssertEqual(failed.messageArguments, [])
        XCTAssertNotNil(failed.systemImageName)
    }

    /// 照会失敗の主要操作は再読込です。
    ///
    /// 責務: `.loadFailed` の `primaryAction` が `.retryLoading` であることを確認します。
    func testLoadFailedPrimaryActionIsRetry() {
        XCTAssertEqual(UnassignedObservedVINWarning.loadFailed.primaryAction, .retryLoading)
    }

    /// 1台だけなら主要操作はそのVINを伴う車両登録です。
    ///
    /// 責務: 未登録警告の `primaryAction` が観測VINを運ぶことを確認します。
    func testSingleVehiclePrimaryActionCarriesObservedVIN() {
        XCTAssertEqual(warning(vins: [Fixture.firstVIN]).primaryAction, .registerVehicle(vin: Fixture.firstVIN))
    }

    /// 複数台なら主要操作は最も新しいセッションのVINを伴う車両登録です。
    ///
    /// 責務: 入力順が新しい順でも古い順でも、開始時刻が最新のセッションのVINが選ばれることを確認します。
    func testManyVehiclesPrimaryActionCarriesNewestVIN() {
        let oldest = Fixture.session(vin: Fixture.firstVIN, startedAt: 10)
        let newest = Fixture.session(vin: Fixture.thirdVIN, startedAt: 30)
        let middle = Fixture.session(vin: Fixture.secondVIN, startedAt: 20)
        let expected = UnassignedObservedVINWarningPrimaryAction.registerVehicle(vin: Fixture.thirdVIN)
        XCTAssertEqual(UnassignedObservedVINWarning(sessions: [newest, middle, oldest]).primaryAction, expected)
        XCTAssertEqual(UnassignedObservedVINWarning(sessions: [oldest, middle, newest]).primaryAction, expected)
    }
}

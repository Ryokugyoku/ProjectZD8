import Foundation
@testable import ProjectZD8

/// 未登録車両の警告テストで使う「車両未割当かつ観測VINあり」のセッションを作ります。
enum UnassignedObservedVINSessionFixture {
    /// テストで使うアカウント識別子です。
    static let accountIdentifier = "account-unit5"
    /// 1台目の観測VINです。
    static let firstVIN = "JF1ZD8A11P9000001"
    /// 2台目の観測VINです。
    static let secondVIN = "JF1ZD8A11P9000002"
    /// 3台目の観測VINです。
    static let thirdVIN = "JF1ZD8A11P9000003"

    /// 車両未割当で指定VINを観測したセッションを作ります。
    ///
    /// 責務: 開始時刻を秒で指定した1件のセッションを返します。
    /// - Parameters:
    ///   - vin: 観測VIN。
    ///   - startedAt: 1970年からの秒数で表した開始時刻。
    /// - Returns: 車両未割当のセッション。
    static func session(vin: String, startedAt: TimeInterval) -> ConnectionSession {
        ConnectionSession(
            accountIdentifier: accountIdentifier,
            startedAt: Date(timeIntervalSince1970: startedAt),
            observedVIN: vin
        )
    }
}

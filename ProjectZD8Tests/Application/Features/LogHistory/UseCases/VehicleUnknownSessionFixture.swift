import Foundation
@testable import ProjectZD8

/// 車両不明ログ(終了済み・車両なし・観測VINなし)のテストで使うセッションと車両を作ります。
enum VehicleUnknownSessionFixture {
    /// テストで使うアカウント識別子です。
    static let accountIdentifier = "account-u4b"

    /// 紐付け先の登録済み車両です。
    static let vehicle = VehicleProfile(
        id: VehicleID(rawValue: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!),
        vin: "JF1ZD8A11P9000004",
        name: "BRZ"
    )

    /// 別の登録済み車両です。
    static let otherVehicle = VehicleProfile(
        id: VehicleID(rawValue: UUID(uuidString: "40000000-0000-0000-0000-000000000005")!),
        vin: "JF1ZD8A11P9000005",
        name: "GR86"
    )

    /// 終了済みで車両も観測VINも持たないセッションを作ります。
    ///
    /// 責務: 開始時刻を秒で指定した1件の車両不明ログを返します。
    /// - Parameters:
    ///   - startedAt: 1970年からの秒数で表した開始時刻。
    ///   - account: 所有アカウント識別子。
    /// - Returns: 車両不明ログ。
    static func session(startedAt: TimeInterval, account: String = accountIdentifier) -> ConnectionSession {
        var session = ConnectionSession(accountIdentifier: account, startedAt: Date(timeIntervalSince1970: startedAt))
        session.endedAt = Date(timeIntervalSince1970: startedAt + 60)
        session.endReason = .connectionLost
        return session
    }
}

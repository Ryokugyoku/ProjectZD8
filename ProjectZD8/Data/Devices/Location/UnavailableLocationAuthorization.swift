import Foundation

/// 位置を扱わないプラットフォーム(macOS)用の許可の境界です。常に `unsupportedPlatform` を返し、要求は何もしません。
@MainActor
final class UnavailableLocationAuthorization: LocationAuthorizationPort {
    /// 状態を持たない許可の境界を生成します。
    ///
    /// 責務: 常に未対応を返す許可の境界を構築します。
    init() {}

    /// 現在の許可状態。常に `unsupportedPlatform` です。
    var currentPermission: LocationPermission { .unsupportedPlatform }

    /// 何も流さずにすぐ終わる許可状態の流れを返します。
    ///
    /// 責務: 許可状態が変わらないことを、終了済みの流れで表します。
    /// - Returns: 要素のない終了済みの流れ。
    func permissionChanges() -> AsyncStream<LocationPermission> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    /// 何もしません。
    ///
    /// 責務: 未対応のプラットフォームでは許可を要求しません。
    func requestWhenInUseAuthorization() {}

    /// 何もしません。
    ///
    /// 責務: 未対応のプラットフォームでは許可を要求しません。
    func requestAlwaysAuthorization() {}
}

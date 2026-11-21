import CryptoKit
import Foundation

/// CloudKit レコードの整合性確認とアカウントの同期範囲に使う SHA-256 を算出します。
///
/// 算出方法は `CloudKitConnectionSessionTransferRepository` の private 実装(`sha256` と `fingerprint`)と同じです。
nonisolated enum CloudKitRecordDigest {
    /// バイト列の SHA-256 を小文字16進64文字で返します。
    ///
    /// 責務: 1件のバイト列を、転送の整合性確認に使う安定した digest へ変換します。
    /// - Parameter data: digest を計算するバイト列。
    /// - Returns: 小文字16進64文字の SHA-256。
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// アカウント識別子を、元に戻せない同期範囲の識別値へ変換します。
    ///
    /// 責務: 識別子の UTF-8 バイト列の SHA-256 を小文字16進で返します。
    /// - Parameter accountIdentifier: アプリ固有の Apple アカウント識別子。
    /// - Returns: 小文字16進64文字の fingerprint。
    static func accountFingerprint(for accountIdentifier: String) -> String {
        sha256Hex(Data(accountIdentifier.utf8))
    }
}

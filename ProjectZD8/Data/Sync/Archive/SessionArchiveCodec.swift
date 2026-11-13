import CryptoKit
import Foundation

/// `SessionArchive` を端末間で受け渡すバイト列へ変換します。
///
/// 形式: キーを整列したJSON(日時はエポックミリ秒、バイト列はBase64)→ zlib圧縮。
/// 検証値は圧縮後のバイト列のSHA-256(小文字16進)です。
nonisolated struct SessionArchiveCodec: Sendable {
    /// 責務: コーデックを生成します。
    init() {}

    /// 責務: アーカイブをJSON化して圧縮し、検証値を付けて返します。
    /// - Throws: JSON化または圧縮に失敗した場合のエラー。
    func encode(_ archive: SessionArchive) throws -> EncodedSessionArchive {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.dataEncodingStrategy = .base64
        let json = try encoder.encode(archive)
        let compressed = try (json as NSData).compressed(using: .zlib) as Data
        return EncodedSessionArchive(data: compressed, digest: Self.digest(of: compressed))
    }

    /// 責務: 検証値と形式版を確かめてからアーカイブを復元します。
    /// - Parameters:
    ///   - data: 圧縮済みのバイト列。
    ///   - expectedDigest: レコードに記録された検証値。
    /// - Throws: `SessionArchiveCodecError`。
    func decode(_ data: Data, expectedDigest: String) throws -> SessionArchive {
        guard Self.digest(of: data) == expectedDigest.lowercased() else { throw SessionArchiveCodecError.digestMismatch }
        let json: Data
        do {
            json = try (data as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw SessionArchiveCodecError.malformed
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        decoder.dataDecodingStrategy = .base64
        let header: SessionArchiveFormatHeader
        do {
            header = try decoder.decode(SessionArchiveFormatHeader.self, from: json)
        } catch {
            throw SessionArchiveCodecError.malformed
        }
        guard header.formatVersion == SessionArchive.currentFormatVersion else {
            throw SessionArchiveCodecError.unsupportedFormatVersion(header.formatVersion)
        }
        do {
            return try decoder.decode(SessionArchive.self, from: json)
        } catch {
            throw SessionArchiveCodecError.malformed
        }
    }

    /// 責務: バイト列のSHA-256を小文字16進で返します。
    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// 本体を復号する前に形式版だけを読むための見出しです。
private nonisolated struct SessionArchiveFormatHeader: Decodable {
    let formatVersion: Int
}

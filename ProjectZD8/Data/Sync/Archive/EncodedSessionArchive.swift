import Foundation

/// 圧縮済みのセッションアーカイブとその検証値です。
nonisolated struct EncodedSessionArchive: Equatable, Sendable {
    /// zlibで圧縮したJSONのバイト列です。CloudKitのアセットの中身になります。
    let data: Data
    /// `data` のSHA-256(小文字16進)です。
    let digest: String

    /// 責務: 圧縮済みアーカイブと検証値をまとめます。
    init(data: Data, digest: String) {
        self.data = data
        self.digest = digest
    }
}

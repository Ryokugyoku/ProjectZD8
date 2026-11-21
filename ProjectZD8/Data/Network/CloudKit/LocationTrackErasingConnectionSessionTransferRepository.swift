import Foundation

/// 既存の転送 Repository の削除に、走行ルート(位置の軌跡)の iCloud 削除を足すデコレーターです。
///
/// プロトコルの13個の要件をすべて明示的に base へ転送します(書き忘れると extension の既定実装が黙って使われるため)。
/// `deleteSession` と `deleteAll` だけ、base の後に軌跡を削除します。base が失敗したら軌跡は削除しません。
/// エラーは包まずにそのまま投げ直します(`CloudKitAccountDeletionFailureClassifier` の分類を保つため)。
@MainActor
final class LocationTrackErasingConnectionSessionTransferRepository: ConnectionSessionTransferRepository {
    /// 処理を委ねる既存の転送 Repository です。
    private let base: any ConnectionSessionTransferRepository
    /// 削除を足す軌跡の iCloud Repository です。
    private let locationTracks: any ConnectionSessionLocationTrackCloudRepository

    /// 委譲先と軌跡の削除先を固定して生成します。
    ///
    /// 責務: 既存の転送 Repository と軌跡の Repository を組み合わせます。
    /// - Parameters:
    ///   - base: 処理を委ねる既存の転送 Repository。
    ///   - locationTracks: 削除を足す軌跡の iCloud Repository。
    init(
        base: any ConnectionSessionTransferRepository,
        locationTracks: any ConnectionSessionLocationTrackCloudRepository
    ) {
        self.base = base
        self.locationTracks = locationTracks
    }

    /// セッション概要の保存を base へ委ねます。
    ///
    /// 責務: 引数をそのまま base へ転送します。
    func publishMetadata(_ metadata: ConnectionSessionCloudMetadata, for accountIdentifier: String) async throws {
        try await base.publishMetadata(metadata, for: accountIdentifier)
    }

    /// セッション概要の取得を base へ委ねます。
    ///
    /// 責務: 引数と返り値をそのまま base と受け渡します。
    func downloadMetadata(for accountIdentifier: String) async throws -> [ConnectionSessionCloudMetadata] {
        try await base.downloadMetadata(for: accountIdentifier)
    }

    /// Raw Manifest の取得を base へ委ねます。
    ///
    /// 責務: 引数と返り値をそのまま base と受け渡します。
    func downloadTransferManifests(for accountIdentifier: String) async throws -> [ConnectionSessionID: String] {
        try await base.downloadTransferManifests(for: accountIdentifier)
    }

    /// Raw Payload の取得を base へ委ねます。
    ///
    /// 責務: 引数と返り値をそのまま base と受け渡します。
    func downloadTransfer(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws -> VerifiedConnectionSessionTransfer {
        try await base.downloadTransfer(sessionID: sessionID, for: accountIdentifier)
    }

    /// 進捗付きの Raw Payload の取得を base へ委ねます。
    ///
    /// 責務: 引数・進捗通知・返り値をそのまま base と受け渡します。
    func downloadTransfer(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> VerifiedConnectionSessionTransfer {
        try await base.downloadTransfer(sessionID: sessionID, for: accountIdentifier, progress: progress)
    }

    /// Raw Payload の保存を base へ委ねます。
    ///
    /// 責務: 引数と返り値をそのまま base と受け渡します。
    func upload(_ package: ConnectionSessionTransferPackage, for accountIdentifier: String) async throws -> String {
        try await base.upload(package, for: accountIdentifier)
    }

    /// 進捗付きの Raw Payload の保存を base へ委ねます。
    ///
    /// 責務: 引数・進捗通知・返り値をそのまま base と受け渡します。
    func upload(
        _ package: ConnectionSessionTransferPackage,
        for accountIdentifier: String,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> String {
        try await base.upload(package, for: accountIdentifier, progress: progress)
    }

    /// 全 Raw Payload の取得を base へ委ねます。
    ///
    /// 責務: 引数と返り値をそのまま base と受け渡します。
    func downloadTransfers(for accountIdentifier: String) async throws -> [VerifiedConnectionSessionTransfer] {
        try await base.downloadTransfers(for: accountIdentifier)
    }

    /// Mac 取込受領証の保存を base へ委ねます。
    ///
    /// 責務: 引数をそのまま base へ転送します。
    func publishMacReceipt(
        _ receipt: ConnectionSessionMacImportReceipt,
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws {
        try await base.publishMacReceipt(receipt, sessionID: sessionID, for: accountIdentifier)
    }

    /// Mac 取込受領証の取得を base へ委ねます。
    ///
    /// 責務: 引数と返り値をそのまま base と受け渡します。
    func downloadMacReceipts(
        for accountIdentifier: String
    ) async throws -> [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] {
        try await base.downloadMacReceipts(for: accountIdentifier)
    }

    /// 削除マーカーの取得を base へ委ねます。
    ///
    /// 責務: 引数と返り値をそのまま base と受け渡します。
    func deletedSessionIDs(for accountIdentifier: String) async throws -> Set<ConnectionSessionID> {
        try await base.deletedSessionIDs(for: accountIdentifier)
    }

    /// セッションを全端末削除し、続けてその軌跡を iCloud から削除します。
    ///
    /// 責務: base の削除が成功した時だけ軌跡を削除し、どちらのエラーも包まずに投げます。
    func deleteSession(_ sessionID: ConnectionSessionID, for accountIdentifier: String) async throws {
        try await base.deleteSession(sessionID, for: accountIdentifier)
        try await locationTracks.delete(sessionID: sessionID, for: accountIdentifier)
    }

    /// アカウントの運転データを削除し、続けてその軌跡をすべて iCloud から削除します。
    ///
    /// 責務: base の削除が成功した時だけ軌跡を削除し、どちらのエラーも包まずに投げます。
    func deleteAll(for accountIdentifier: String) async throws {
        try await base.deleteAll(for: accountIdentifier)
        try await locationTracks.deleteAll(for: accountIdentifier)
    }
}

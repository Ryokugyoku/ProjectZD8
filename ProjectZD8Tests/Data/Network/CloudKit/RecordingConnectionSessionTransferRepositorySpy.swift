import Foundation
@testable import ProjectZD8

/// `ConnectionSessionTransferRepository` の13個の要件すべてについて、呼び出しと引数を順に記録し、
/// 設定した値を返すか、設定したエラーを投げる Spy です(extension の既定実装には頼りません)。
@MainActor
final class RecordingConnectionSessionTransferRepositorySpy: ConnectionSessionTransferRepository {
    /// 記録する呼び出しです(要件ごとに1つ。進捗つきの版は別に数えます)。
    enum Call: Equatable {
        /// `publishMetadata(_:for:)`。
        case publishMetadata(ConnectionSessionCloudMetadata, accountIdentifier: String)
        /// `downloadMetadata(for:)`。
        case downloadMetadata(accountIdentifier: String)
        /// `downloadTransferManifests(for:)`。
        case downloadTransferManifests(accountIdentifier: String)
        /// `downloadTransfer(sessionID:for:)`。
        case downloadTransfer(ConnectionSessionID, accountIdentifier: String)
        /// `downloadTransfer(sessionID:for:progress:)`。
        case downloadTransferWithProgress(ConnectionSessionID, accountIdentifier: String)
        /// `upload(_:for:)`。
        case upload(ConnectionSessionTransferPackage, accountIdentifier: String)
        /// `upload(_:for:progress:)`。
        case uploadWithProgress(ConnectionSessionTransferPackage, accountIdentifier: String)
        /// `downloadTransfers(for:)`。
        case downloadTransfers(accountIdentifier: String)
        /// `publishMacReceipt(_:sessionID:for:)`。
        case publishMacReceipt(ConnectionSessionMacImportReceipt, ConnectionSessionID, accountIdentifier: String)
        /// `downloadMacReceipts(for:)`。
        case downloadMacReceipts(accountIdentifier: String)
        /// `deletedSessionIDs(for:)`。
        case deletedSessionIDs(accountIdentifier: String)
        /// `deleteSession(_:for:)`。
        case deleteSession(ConnectionSessionID, accountIdentifier: String)
        /// `deleteAll(for:)`。
        case deleteAll(accountIdentifier: String)
    }

    /// 呼ばれた順の呼び出しの記録です。
    private(set) var calls: [Call] = []
    /// 呼び出しのたびに、記録の後で通知する動作です(他の Fake との順序の検証に使います)。
    var onCall: (@MainActor (Call) -> Void)?
    /// 全要件で投げるエラーです(`nil` なら設定した値を返します)。
    var error: (any Error)?
    /// 進捗つきの要件で、渡された進捗へ順に通知する値です。
    var progressValues: [Double] = [0.25, 0.75]
    /// `downloadMetadata` が返す値です。
    var metadataToReturn: [ConnectionSessionCloudMetadata] = []
    /// `downloadTransferManifests` が返す値です。
    var manifestsToReturn: [ConnectionSessionID: String] = [:]
    /// `downloadTransfer` の2つの版が返す値です。
    var transferToReturn = VerifiedConnectionSessionTransfer(
        package: ConnectionSessionTransferPackage(sessionID: ConnectionSessionID(), accountIdentifier: "spy", entries: []),
        manifestDigest: "spy-transfer"
    )
    /// `upload` の2つの版が返す digest です。
    var digestToReturn = "spy-digest"
    /// `downloadTransfers` が返す値です。
    var transfersToReturn: [VerifiedConnectionSessionTransfer] = []
    /// `downloadMacReceipts` が返す値です。
    var receiptsToReturn: [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] = []
    /// `deletedSessionIDs` が返す値です。
    var deletedIDsToReturn: Set<ConnectionSessionID> = []

    /// 空の Spy を生成します。
    ///
    /// 責務: 何も記録しておらず、エラーも設定していない状態を構築します。
    init() {}

    /// 責務: 呼び出しを記録し、設定したエラーがあれば投げます。
    /// - Parameters:
    ///   - metadata: 公開する概要。
    ///   - accountIdentifier: アカウント識別子。
    func publishMetadata(_ metadata: ConnectionSessionCloudMetadata, for accountIdentifier: String) async throws {
        try record(.publishMetadata(metadata, accountIdentifier: accountIdentifier))
    }

    /// 責務: 呼び出しを記録し、設定した概要を返します。
    /// - Parameter accountIdentifier: アカウント識別子。
    /// - Returns: 設定した概要。
    func downloadMetadata(for accountIdentifier: String) async throws -> [ConnectionSessionCloudMetadata] {
        try record(.downloadMetadata(accountIdentifier: accountIdentifier))
        return metadataToReturn
    }

    /// 責務: 呼び出しを記録し、設定した manifest を返します。
    /// - Parameter accountIdentifier: アカウント識別子。
    /// - Returns: 設定した manifest。
    func downloadTransferManifests(for accountIdentifier: String) async throws -> [ConnectionSessionID: String] {
        try record(.downloadTransferManifests(accountIdentifier: accountIdentifier))
        return manifestsToReturn
    }

    /// 責務: 呼び出しを記録し、設定した転送を返します。
    /// - Parameters:
    ///   - sessionID: 対象のセッション。
    ///   - accountIdentifier: アカウント識別子。
    /// - Returns: 設定した転送。
    func downloadTransfer(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws -> VerifiedConnectionSessionTransfer {
        try record(.downloadTransfer(sessionID, accountIdentifier: accountIdentifier))
        return transferToReturn
    }

    /// 責務: 呼び出しを記録し、設定した進捗を通知してから、設定した転送を返します。
    /// - Parameters:
    ///   - sessionID: 対象のセッション。
    ///   - accountIdentifier: アカウント識別子。
    ///   - progress: 進捗の通知先。
    /// - Returns: 設定した転送。
    func downloadTransfer(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> VerifiedConnectionSessionTransfer {
        try record(.downloadTransferWithProgress(sessionID, accountIdentifier: accountIdentifier))
        progressValues.forEach(progress)
        return transferToReturn
    }

    /// 責務: 呼び出しを記録し、設定した digest を返します。
    /// - Parameters:
    ///   - package: 送る転送。
    ///   - accountIdentifier: アカウント識別子。
    /// - Returns: 設定した digest。
    func upload(_ package: ConnectionSessionTransferPackage, for accountIdentifier: String) async throws -> String {
        try record(.upload(package, accountIdentifier: accountIdentifier))
        return digestToReturn
    }

    /// 責務: 呼び出しを記録し、設定した進捗を通知してから、設定した digest を返します。
    /// - Parameters:
    ///   - package: 送る転送。
    ///   - accountIdentifier: アカウント識別子。
    ///   - progress: 進捗の通知先。
    /// - Returns: 設定した digest。
    func upload(
        _ package: ConnectionSessionTransferPackage,
        for accountIdentifier: String,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> String {
        try record(.uploadWithProgress(package, accountIdentifier: accountIdentifier))
        progressValues.forEach(progress)
        return digestToReturn
    }

    /// 責務: 呼び出しを記録し、設定した転送の一覧を返します。
    /// - Parameter accountIdentifier: アカウント識別子。
    /// - Returns: 設定した転送の一覧。
    func downloadTransfers(for accountIdentifier: String) async throws -> [VerifiedConnectionSessionTransfer] {
        try record(.downloadTransfers(accountIdentifier: accountIdentifier))
        return transfersToReturn
    }

    /// 責務: 呼び出しを記録し、設定したエラーがあれば投げます。
    /// - Parameters:
    ///   - receipt: 公開する受領証。
    ///   - sessionID: 対象のセッション。
    ///   - accountIdentifier: アカウント識別子。
    func publishMacReceipt(
        _ receipt: ConnectionSessionMacImportReceipt,
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws {
        try record(.publishMacReceipt(receipt, sessionID, accountIdentifier: accountIdentifier))
    }

    /// 責務: 呼び出しを記録し、設定した受領証を返します。
    /// - Parameter accountIdentifier: アカウント識別子。
    /// - Returns: 設定した受領証。
    func downloadMacReceipts(
        for accountIdentifier: String
    ) async throws -> [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] {
        try record(.downloadMacReceipts(accountIdentifier: accountIdentifier))
        return receiptsToReturn
    }

    /// 責務: 呼び出しを記録し、設定した削除済みのセッション ID を返します。
    /// - Parameter accountIdentifier: アカウント識別子。
    /// - Returns: 設定した削除済みのセッション ID。
    func deletedSessionIDs(for accountIdentifier: String) async throws -> Set<ConnectionSessionID> {
        try record(.deletedSessionIDs(accountIdentifier: accountIdentifier))
        return deletedIDsToReturn
    }

    /// 責務: 呼び出しを記録し、設定したエラーがあれば投げます。
    /// - Parameters:
    ///   - sessionID: 対象のセッション。
    ///   - accountIdentifier: アカウント識別子。
    func deleteSession(_ sessionID: ConnectionSessionID, for accountIdentifier: String) async throws {
        try record(.deleteSession(sessionID, accountIdentifier: accountIdentifier))
    }

    /// 責務: 呼び出しを記録し、設定したエラーがあれば投げます。
    /// - Parameter accountIdentifier: アカウント識別子。
    func deleteAll(for accountIdentifier: String) async throws {
        try record(.deleteAll(accountIdentifier: accountIdentifier))
    }

    /// 呼び出しを記録して通知し、設定したエラーがあれば投げます。
    ///
    /// 責務: 記録・通知・失敗を全要件で同じ順序に行います。
    /// - Parameter call: 記録する呼び出し。
    /// - Throws: 設定したエラー。
    private func record(_ call: Call) throws {
        calls.append(call)
        onCall?(call)
        if let error { throw error }
    }
}

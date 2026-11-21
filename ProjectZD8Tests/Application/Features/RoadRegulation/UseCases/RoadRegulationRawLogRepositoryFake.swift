import Foundation
@testable import ProjectZD8

/// 規制の判定のテストで使う Raw ログの Repository の偽物です。
///
/// ページごとの読み出し(`entries(for:after:limit:)`)の呼び出しを記録し、失敗の注入、呼び出しごとの割り込み、
/// 連番の進まないページを返し続ける動き(読み手が止まることの確認用)を持ちます。全件の読み出しは使われたことを数えます。
final class RoadRegulationRawLogRepositoryFake: ConnectionSessionRawLogRepository {
    /// ページの読み出しの1回分です。
    struct PageRequest: Equatable {
        /// この連番より後を読む(`nil` なら最初から)。
        let after: Int64?
        /// 読む件数の上限。
        let limit: Int
    }

    /// 返す Raw ログです(連番の昇順)。
    var storedEntries: [ConnectionSessionRawLogEntry] = []
    /// 投げるエラーです。
    var error: ConnectionSessionRepositoryError?
    /// `true` なら、`after` に関係なく最初のページを返し続けます。
    var repeatsFirstPage = false
    /// ページの読み出しのたびに、何回目(1始まり)かを渡して呼ぶ割り込みです。
    var onPageRequest: ((Int) -> Void)?
    /// ページの読み出しの記録です。
    private(set) var pageRequests: [PageRequest] = []
    /// 全件の読み出しが呼ばれた回数です。
    private(set) var fullReadCount = 0

    /// 責務: 全件の読み出しを数え、失敗の指定があれば投げ、なければ全件を返します。
    func entries(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionRawLogEntry] {
        fullReadCount += 1
        if let error { throw error }
        return storedEntries
    }

    /// 責務: ページの読み出しを記録して割り込みを呼び、失敗の指定があれば投げ、なければ連番が `after` より後の先頭 `limit` 件を返します。
    func entries(for sessionID: ConnectionSessionID, after sequence: Int64?, limit: Int) throws -> [ConnectionSessionRawLogEntry] {
        pageRequests.append(PageRequest(after: sequence, limit: limit))
        onPageRequest?(pageRequests.count)
        if let error { throw error }
        let lowerBound = repeatsFirstPage ? -1 : (sequence ?? -1)
        return Array(storedEntries.filter { $0.sequence > lowerBound }.prefix(max(0, limit)))
    }

    /// 責務: このテストでは使わない車両別の読み出しに空配列を返します。
    func entries(for vehicleID: VehicleID, accountIdentifier: String) throws -> [VehicleConnectionSessionRawLogEntry] { [] }
    /// 責務: このテストでは使わない CloudKit の保存結果を受け流します。
    func markCloudUploaded(sessionID: ConnectionSessionID, manifestDigest: String) throws {}
    /// 責務: このテストでは使わない CloudKit の失敗を受け流します。
    func markCloudUploadFailed(sessionID: ConnectionSessionID) throws {}
    /// 責務: このテストでは使わない Mac の取り込み結果を受け流します。
    func markMacImported(_ receipt: ConnectionSessionMacImportReceipt, sessionID: ConnectionSessionID) throws {}
    /// 責務: このテストでは使わない転送の取り込みを受け流します。
    func importVerifiedTransfer(_ transfer: VerifiedConnectionSessionTransfer) throws {}
    /// 責務: このテストでは使わないローカルの削除を受け流します。
    func removeLocalEntries(for sessionID: ConnectionSessionID) throws {}
}

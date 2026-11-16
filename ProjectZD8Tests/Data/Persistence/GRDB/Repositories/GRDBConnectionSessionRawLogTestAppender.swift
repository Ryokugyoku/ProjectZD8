import Foundation
import GRDB
@testable import ProjectZD8

/// テストの前準備で、未終了セッションへRaw応答を1件ずつ採番して追記する部品です。
///
/// 削除した `GRDBConnectionSessionRepository.append(_:to:)` と同じ書き込み(1件ごとの書き込みトランザクションで
/// `GRDBConnectionSessionRawLogAppender` が採番し、親セッションの集計を更新する)を行い、検証内容を変えずに前準備を再現します。
struct GRDBConnectionSessionRawLogTestAppender {
    /// 書き込み先のDB Queueです。検証対象のRepositoryと同じQueueを渡します。
    let queue: DatabaseQueue

    /// 1件のRaw応答を指定セッションの次の順序へ追記します。
    ///
    /// 責務: 1回の書き込みトランザクションで採番追記と親集計の更新を行います。
    /// - Parameters:
    ///   - observation: 追記する未デコード応答。
    ///   - sessionID: 追記先の未終了セッションID。
    /// - Throws: セッション不在・終了済み(`ConnectionSessionRepositoryError.invalidState`)、またはSQLite書込み失敗。
    func append(_ observation: OBDRawResponseObservation, to sessionID: ConnectionSessionID) throws {
        try queue.write { database in
            _ = try GRDBConnectionSessionRawLogAppender().appendNextSequence(observation, to: sessionID, in: database)
        }
    }
}

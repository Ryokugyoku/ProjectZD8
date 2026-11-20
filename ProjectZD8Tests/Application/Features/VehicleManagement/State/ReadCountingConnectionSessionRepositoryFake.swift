import Foundation
@testable import ProjectZD8

/// セッションの読込回数を数え、保存・終了は内側の可変 fake へ委ねる接続セッション Repository の fake です。
final class ReadCountingConnectionSessionRepositoryFake: ConnectionSessionRepository {
    /// 保存と終了を受け持つ内側の fake です。
    let storage = MutableConnectionSessionRepositoryFake()

    /// `sessions(for:)` が呼ばれた回数です。
    private(set) var readCount = 0

    /// 空の保存状態で生成します。
    ///
    /// 責務: セッションを1件も持たず、読込回数が0の fake を作ります。
    init() {}

    /// セッションを内側の fake へ保存します。
    ///
    /// 責務: 1件のセッションの現在内容を内側の fake へ渡します。
    /// - Parameter session: 保存するセッション。
    func save(_ session: ConnectionSession) throws {
        try storage.save(session)
    }

    /// 読込を数えて、指定アカウントのセッションを返します。
    ///
    /// 責務: 読込回数を1つ増やし、内側の fake が持つ指定アカウントのセッションを返します。
    /// - Parameter accountIdentifier: 取得対象のアカウント識別子。
    /// - Returns: そのアカウントのセッション。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession] {
        readCount += 1
        return try storage.sessions(for: accountIdentifier)
    }
}

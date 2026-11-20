import Foundation

/// 記録中のセッションをシステムの常時表示(iOSのLive Activity)として出す境界です。
///
/// 失敗は throw で返します。成功扱いにして黙って捨てないこと。表示がシステムやユーザーに閉じられたかどうかは
/// `isPresenting` で問えます。
@MainActor
protocol SessionActivityPort: AnyObject {
    /// このプロセスが開始した表示が、いまシステム上に出ているかどうかです。
    ///
    /// 終了済み・システムによる終了(8時間上限等)・ユーザーによる消去の後は `false` です。
    var isPresenting: Bool { get }

    /// 表示を開始します。前のプロセスが残した表示があれば閉じてから開始します。
    ///
    /// 責務: 1件の表示内容と有効期限でシステムへ表示開始を要求します。
    /// - Parameters:
    ///   - content: 最初に出す表示内容。
    ///   - staleDate: 次の更新が届かなければ表示が古い扱いになる時刻。
    /// - Throws: 表示が許可されていない、またはシステムが開始を断った場合。
    func start(_ content: RecordingSessionActivityContent, staleDate: Date) async throws

    /// 出ている表示の内容を更新します。
    ///
    /// 責務: 1件の表示内容と有効期限でシステム上の表示を置き換えます。
    /// - Parameters:
    ///   - content: 新しい表示内容。
    ///   - staleDate: 次の更新が届かなければ表示が古い扱いになる時刻。
    /// - Throws: 表示が出ていない場合(`SessionActivityPortError.notPresenting`)など。
    func update(_ content: RecordingSessionActivityContent, staleDate: Date) async throws

    /// 最終内容を出して表示を終了します。
    ///
    /// 責務: 1件の最終表示内容を渡して表示を閉じ、`dismissAt` に自動で消えるようにします。
    /// - Parameters:
    ///   - finalContent: 終了時に出す最終内容。
    ///   - dismissAt: 終了表示を自動で消す時刻。
    /// - Throws: 表示が出ていない場合(`SessionActivityPortError.notPresenting`)など。
    func end(_ finalContent: RecordingSessionActivityContent, dismissAt: Date) async throws

    /// このプロセスが追跡していない、まだ終了していない表示をすべて即時に閉じます。
    ///
    /// 責務: 前回のプロセスが残した表示(開始待ち・表示中・古い扱い)を閉じます。終了済みで消去待ちの終了表示と、
    /// このプロセスが追跡中の表示は閉じません。個々の失敗は実装側で診断へ残し、呼び出し元へは返しません。
    func endOrphanedPresentations() async
}

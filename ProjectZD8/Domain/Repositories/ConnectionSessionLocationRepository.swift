import Foundation

/// 接続セッションの位置と位置記録の状態変化を永続化する能力です。
///
/// 例外の約束: セッション不在・制約違反・保存値をDomainへ復元できない場合は
/// `ConnectionSessionRepositoryError.integrityConflict`、それ以外の保存・読取失敗は `.unavailable`。
nonisolated protocol ConnectionSessionLocationRepository: Sendable {
    /// 位置を1点追記します。
    ///
    /// 責務: 同じ書込みの中で `sequence` を最大値+1で採番して位置を追加します(続行で復帰したセッションでも連番が続きます)。
    /// - Parameters:
    ///   - fix: 保存する位置。
    ///   - sessionID: 位置を所有する接続セッション。
    /// - Throws: セッション不在・制約違反は `ConnectionSessionRepositoryError.integrityConflict`、それ以外は `.unavailable`。
    func appendSample(_ fix: LocationFix, for sessionID: ConnectionSessionID) throws

    /// セッションの位置を返します。
    ///
    /// 責務: 1件のセッションに保存された全位置を安定順で復元します。
    /// - Parameter sessionID: 読取対象の接続セッション。
    /// - Returns: `sequence` 昇順の位置。無ければ空配列。
    /// - Throws: 復元不能は `ConnectionSessionRepositoryError.integrityConflict`、それ以外は `.unavailable`。
    func samples(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionLocationSample]

    /// 位置記録の状態変化を1件追記します。
    ///
    /// 責務: 同じ書込みの中で `ordinal` を採番して状態変化を追加します。
    /// - Parameters:
    ///   - kind: 状態の種類。
    ///   - occurredAt: 状態が変化した実時間。
    ///   - sessionID: 状態変化を所有する接続セッション。
    /// - Throws: セッション不在・制約違反は `ConnectionSessionRepositoryError.integrityConflict`、それ以外は `.unavailable`。
    func appendEvent(
        _ kind: ConnectionSessionLocationEventKind,
        occurredAt: Date,
        for sessionID: ConnectionSessionID
    ) throws

    /// セッションの位置記録の状態変化を返します。
    ///
    /// 責務: 1件のセッションに保存された全状態変化を安定順で復元します。
    /// - Parameter sessionID: 読取対象の接続セッション。
    /// - Returns: `ordinal` 昇順の状態変化。無ければ空配列。
    /// - Throws: 復元不能は `ConnectionSessionRepositoryError.integrityConflict`、それ以外は `.unavailable`。
    func events(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionLocationEvent]
}

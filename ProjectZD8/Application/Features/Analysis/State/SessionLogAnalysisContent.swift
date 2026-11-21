import Foundation

/// セッション解析画面の本文に出す内容の種類です。読込段階と時系列の有無から決まります。
nonisolated enum SessionLogAnalysisContent: Equatable, Sendable {
    /// iCloud から Raw ログを取得中です。`progress` は 0〜1 の取得率です。
    case downloading(progress: Double)
    /// 時系列がまだ1件もない読込中です。
    case initialLoading
    /// 時系列が1件もないまま読込に失敗しました。
    case failedWithoutData
    /// 読込が完了しましたが時系列が1件もありません。
    case empty
    /// 選択中の表示モードの解析結果です。`showsProgress` が真なら逐次変換の進捗も出します。
    case results(showsProgress: Bool)
}

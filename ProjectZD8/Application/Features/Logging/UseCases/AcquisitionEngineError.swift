/// 取得エンジンが呼び出し側へ返す失敗です。
nonisolated enum AcquisitionEngineError: Error, Equatable, Sendable {
    /// 取得エンジンは1セッションにつき1回しか実行できません。
    case alreadyRun
    /// セッションの終了状態を保存できませんでした。引数は終了しようとした理由です。
    case finishFailed(SessionEndReason)
}

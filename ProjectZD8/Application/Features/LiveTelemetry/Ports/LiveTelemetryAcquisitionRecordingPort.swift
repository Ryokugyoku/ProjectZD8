import Foundation

/// 応答駆動の取得ループが受信した要求結果を取得証跡として記録する能力です。
///
/// 呼び出し側は1つの世代について `start` → (`beginRound` → `record`… → `finishRound`)… → `finish` の順に呼びます。
/// `flush` はその間の任意の時点で呼べます。取得が途切れた場合は周回の途中でも `endSegment` を呼び、
/// 復帰したら `beginSegment` を呼んでから周回の記録を再開します(区間が閉じている間は周回を記録しません)。
/// `endSegment` 後に復帰せず終わる場合も `finish` を呼びます。
nonisolated protocol LiveTelemetryAcquisitionRecordingPort: Sendable {
    /// manifestを確定し、セッションの連続取得区間を開始します。
    ///
    /// 責務: 1世代の確定済み取得入力を記録受付可能な状態へ変換します。
    /// - Parameter input: 定義、capability、基準要求順を含む取得開始入力。
    /// - Throws: セッション不在、入力不正、または保存失敗。
    func start(_ input: LiveTelemetryAcquisitionStartInput) async throws

    /// 1周回(1 batch)の開始を記録します。
    ///
    /// 責務: 周回の識別子と要求列を未完了のbatchとして保持します。
    /// - Parameter input: 周回の識別子と要求列。
    /// - Throws: 世代不一致、順序不正、または保存を続けられない状態。
    func beginRound(_ input: LiveTelemetryAcquisitionRoundInput) async throws

    /// 要求1件の結果を記録します。
    ///
    /// 責務: 1件の要求結果を保存待ちの記録へ追加し、必要なら保存します。
    /// - Parameter result: 要求1件の結果。
    /// - Throws: 世代不一致、順序不正、または保存も欠損記録もできない場合。
    func record(_ result: LiveTelemetryRequestResult) async throws

    /// 1周回の全要求が終わったことを記録します。
    ///
    /// 責務: 未完了のbatchを終端状態へ確定し、必要なら保存します。
    /// - Parameters:
    ///   - generation: 取得ループが所有する世代。
    ///   - batchOrdinal: 終える周回のbatch番号。
    /// - Throws: 世代不一致、順序不正、または保存も欠損記録もできない場合。
    func finishRound(generation: UInt, batchOrdinal: Int64) async throws

    /// 件数や経過時間にかかわらず保存待ちの記録を保存します。
    ///
    /// 責務: 指定契機で保存可能な記録をすべて保存します。
    /// - Parameters:
    ///   - trigger: 保存の契機。
    ///   - generation: 取得ループが所有する世代。開始前・終了後の世代では何もしません。
    /// - Throws: 保存も欠損記録もできない場合。
    func flush(_ trigger: LiveTelemetryAcquisitionFlushTrigger, generation: UInt) async throws

    /// 取得が途切れたため、現在の連続取得区間を閉じます。
    ///
    /// 責務: 未完了のbatchを打ち切って保存待ちの記録をすべて保存し、区間を指定原因で終了します。
    /// 以後 `beginSegment` まで周回・受信の記録を受け付けません。
    /// - Parameters:
    ///   - generation: 取得ループが所有する世代。
    ///   - reason: 区間が終わった直接原因(`responseStall` または `linkLost`)。
    ///   - lastReceivedAt: 最後に正応答を受信した実時間。区間の終了時刻に使います。
    /// - Throws: 世代不一致、区間が開いていない場合、または保存も欠損記録もできない場合。
    func endSegment(generation: UInt, reason: ConnectionSessionSegmentEndReason, lastReceivedAt: Date) async throws

    /// 途絶から復帰したため、欠損を挟んで次の連続取得区間を開きます。
    ///
    /// 責務: 欠損1件と次の区間1件を保存し、Rawの記録順序を前の区間から続けます。
    /// - Parameter input: 世代、開始理由、欠損の原因と開始時刻。
    /// - Throws: 世代不一致、区間が開いたままの場合、または保存失敗。
    func beginSegment(_ input: LiveTelemetryAcquisitionSegmentResumption) async throws

    /// 取得を終え、保存待ちの記録と連続取得区間を閉じます。
    ///
    /// 責務: 1世代の未完了batchを打ち切り、残りを保存して区間を終了します。
    /// - Parameters:
    ///   - generation: 終える世代。現在の世代でなければ何もしません。
    ///   - reason: 取得が終わった直接原因。
    /// - Throws: 保存も欠損記録もできない場合、または区間を終了できない場合。
    func finish(generation: UInt, reason: ConnectionSessionEndReason) async throws
}

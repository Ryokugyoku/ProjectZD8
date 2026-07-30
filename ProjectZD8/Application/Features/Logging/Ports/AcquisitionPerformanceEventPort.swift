/// 取得性能として区間計測する匿名操作です。
nonisolated enum AcquisitionPerformanceOperation: String, Equatable, Sendable {
    /// 1世代のmanifest作成を含む取得開始です。
    case acquisitionStart
    /// manifestと取得開始境界の原子保存です。
    case manifestPersistence
    /// open batch metadataの保存です。
    case batchOpenPersistence
    /// request dispatch開始状態の保存です。
    case requestDispatchPersistence
    /// physical requestからtyped observationまでの通信です。
    case requestTransport
    /// responded Rawとterminal evidenceの原子保存です。
    case respondedPersistence
    /// Rawを持たないterminal evidenceの保存です。
    case nonRespondedPersistence
    /// terminal batchのseal保存です。
    case batchSealPersistence
    /// Production loopにおける1 batch全体の取得です。
    case batchAcquisition
    /// stale世代から拒否したbatch取得です。
    case staleBatchRejection
    /// 指定世代からの新規取得を停止する取消処理です。
    case generationCancellation
    /// sessionと取得終了境界の原子保存です。
    case sessionTerminationPersistence
    /// process終了後に残った取得証拠の回復保存です。
    case terminationRecoveryPersistence
}

/// 性能区間へ付与する匿名の取得位置です。
nonisolated struct AcquisitionPerformanceContext: Equatable, Sendable {
    /// polling workflowの世代です。
    let generation: UInt?
    /// session内のbatch ordinalです。
    let batchOrdinal: Int64?
    /// batch内のrequest ordinalです。
    let requestOrdinal: Int?
    /// polling policyが評価したtickです。
    let policyTick: UInt?
    /// 予定したwake時刻からbatch開始までの非負遅延です。
    let scheduleDelayNanoseconds: UInt64?

    /// 個人・端末・車両識別子を含まない取得位置を生成します。
    ///
    /// 責務: performance eventへ必要な匿名ordinalとschedule遅延だけをまとめます。
    /// - Parameters:
    ///   - generation: polling workflowの世代。
    ///   - batchOrdinal: session内のbatch ordinal。
    ///   - requestOrdinal: batch内のrequest ordinal。
    ///   - policyTick: polling policyが評価したtick。
    ///   - scheduleDelayNanoseconds: 予定wake時刻から実開始までの非負遅延。
    init(
        generation: UInt? = nil,
        batchOrdinal: Int64? = nil,
        requestOrdinal: Int? = nil,
        policyTick: UInt? = nil,
        scheduleDelayNanoseconds: UInt64? = nil
    ) {
        self.generation = generation
        self.batchOrdinal = batchOrdinal
        self.requestOrdinal = requestOrdinal
        self.policyTick = policyTick
        self.scheduleDelayNanoseconds = scheduleDelayNanoseconds
    }
}

/// 開始済みperformance区間を終了eventへ結び付けるtokenです。
nonisolated struct AcquisitionPerformanceInterval: Equatable, Sendable {
    /// process内だけで使用する匿名interval番号です。
    let identifier: UInt64
    /// 区間が表す操作です。
    let operation: AcquisitionPerformanceOperation
    /// 区間へ固定した匿名取得位置です。
    let context: AcquisitionPerformanceContext

    /// 匿名番号、操作、取得位置を開始済み区間へ固定します。
    ///
    /// 責務: begin、queue entry、endを同じ匿名performance区間へ関連付けます。
    /// - Parameters:
    ///   - identifier: process内だけで使用する匿名interval番号。
    ///   - operation: 区間が表す操作。
    ///   - context: 区間へ固定する匿名取得位置。
    init(
        identifier: UInt64,
        operation: AcquisitionPerformanceOperation,
        context: AcquisitionPerformanceContext
    ) {
        self.identifier = identifier
        self.operation = operation
        self.context = context
    }
}

/// performance区間が完了した結果です。
nonisolated enum AcquisitionPerformanceOutcome: String, Equatable, Sendable {
    /// 操作が成功しました。
    case succeeded
    /// 操作が失敗しました。
    case failed
    /// 操作がcancelされました。
    case cancelled
}

/// Production取得を匿名performance eventへ通知する境界です。
nonisolated protocol AcquisitionPerformanceEventPort: Sendable {
    /// 匿名取得位置に対するperformance区間を開始します。
    ///
    /// 責務: 1件の取得操作を後続eventと関連付けられる開始済み区間へ変換します。
    /// - Parameters:
    ///   - operation: 計測する取得操作。
    ///   - context: 個人・端末・車両識別子を含まない取得位置。
    /// - Returns: queue entryと終了通知に再利用する匿名区間。
    func begin(
        _ operation: AcquisitionPerformanceOperation,
        context: AcquisitionPerformanceContext
    ) -> AcquisitionPerformanceInterval

    /// DB write closureへ入った時点を通知します。
    ///
    /// 責務: 1件の永続化区間についてcall開始後のQueue通過点を記録します。
    /// - Parameter interval: `begin`が返した同じ永続化区間。
    func queueDidEnter(_ interval: AcquisitionPerformanceInterval)

    /// performance区間を結果付きで終了します。
    ///
    /// 責務: 1件の開始済み取得操作を成功、失敗、cancelのいずれかで閉じます。
    /// - Parameters:
    ///   - interval: `begin`が返した同じ区間。
    ///   - outcome: 区間の完了結果。
    func end(
        _ interval: AcquisitionPerformanceInterval,
        outcome: AcquisitionPerformanceOutcome
    )
}

/// 通常buildでperformance eventを破棄する既定実装です。
nonisolated struct NoOpAcquisitionPerformanceEventPort: AcquisitionPerformanceEventPort {
    /// 副作用のないperformance境界を生成します。
    ///
    /// 責務: 明示測定build以外の取得を計測副作用のない境界へ結び付けます。
    init() {}

    /// eventを出力しない開始済み区間を返します。
    ///
    /// 責務: 1件の取得操作を副作用のない固定tokenへ変換します。
    /// - Parameters:
    ///   - operation: 計測しない取得操作。
    ///   - context: 計測しない匿名取得位置。
    /// - Returns: 後続no-op通知で再利用する固定token。
    func begin(
        _ operation: AcquisitionPerformanceOperation,
        context: AcquisitionPerformanceContext
    ) -> AcquisitionPerformanceInterval {
        AcquisitionPerformanceInterval(identifier: 0, operation: operation, context: context)
    }

    /// Queue通過通知を破棄します。
    ///
    /// 責務: 通常buildのQueue通過を追加副作用なしで受理します。
    /// - Parameter interval: 破棄する区間。
    func queueDidEnter(_ interval: AcquisitionPerformanceInterval) {}

    /// 区間終了通知を破棄します。
    ///
    /// 責務: 通常buildの区間終了を追加副作用なしで受理します。
    /// - Parameters:
    ///   - interval: 破棄する区間。
    ///   - outcome: 破棄する完了結果。
    func end(
        _ interval: AcquisitionPerformanceInterval,
        outcome: AcquisitionPerformanceOutcome
    ) {}
}

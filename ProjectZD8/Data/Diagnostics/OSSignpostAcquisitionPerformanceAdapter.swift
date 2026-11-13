import Foundation
import OSLog

/// 匿名の取得性能区間をApple signpostへ変換します。
final class OSSignpostAcquisitionPerformanceAdapter: @unchecked Sendable, AcquisitionPerformanceEventPort {
    /// Instrumentsで抽出するsignpost logです。
    private let log: OSLog
    /// repository外artifactと照合する匿名run識別子です。
    private let runIdentifier: String
    /// interval番号の採番を直列化するlockです。
    private let identifierLock = NSLock()
    /// 次に割り当てるprocess内interval番号です。
    private var nextIdentifier: UInt64 = 1

    /// 明示された匿名run識別子のsignpost adapterを生成します。
    ///
    /// 責務: 1件の承認済み測定runを専用OSLog categoryへ結び付けます。
    /// - Parameter runIdentifier: repository外artifactと照合するASCII匿名run識別子。
    /// - Precondition: `runIdentifier`は1〜64 byteの英数字、`.`、`_`、`-`だけを含みます。
    init(runIdentifier: String) {
        precondition(Self.isValid(runIdentifier: runIdentifier))
        self.runIdentifier = runIdentifier
        log = OSLog(
            subsystem: Bundle.main.bundleIdentifier ?? "ProjectZD8",
            category: "AcquisitionPerformance"
        )
    }

    /// 有効な匿名run識別子がある場合だけsignpost adapterを生成します。
    ///
    /// 責務: 任意の外部入力をprivacy制約を満たす測定境界または明示的な無効状態へ変換します。
    /// - Parameter runIdentifier: 測定buildへ外部から渡された任意文字列。
    /// - Returns: 1〜64 byteの許可ASCIIだけならadapter、それ以外は `nil`。
    static func makeIfValid(
        runIdentifier: String?
    ) -> OSSignpostAcquisitionPerformanceAdapter? {
        guard let runIdentifier, isValid(runIdentifier: runIdentifier) else { return nil }
        return OSSignpostAcquisitionPerformanceAdapter(runIdentifier: runIdentifier)
    }

    /// 匿名取得位置に対するsignpost intervalを開始します。
    ///
    /// 責務: 1件の取得操作を匿名ordinalだけを含む開始signpostへ変換します。
    /// - Parameters:
    ///   - operation: 計測する取得操作。
    ///   - context: 個人・端末・車両識別子を含まない取得位置。
    /// - Returns: Queue通過と終了signpostに再利用する匿名区間。
    func begin(
        _ operation: AcquisitionPerformanceOperation,
        context: AcquisitionPerformanceContext
    ) -> AcquisitionPerformanceInterval {
        let interval = AcquisitionPerformanceInterval(
            identifier: makeIdentifier(),
            operation: operation,
            context: context
        )
        emit(.begin, interval: interval, outcome: nil)
        return interval
    }

    /// DB write closureへ入った時点を同じsignpost IDで記録します。
    ///
    /// 責務: 1件の永続化区間をQueue待機終了eventへ関連付けます。
    /// - Parameter interval: `begin`が返した同じ永続化区間。
    func queueDidEnter(_ interval: AcquisitionPerformanceInterval) {
        let context = interval.context
        os_signpost(
            .event,
            log: log,
            name: "DatabaseQueueEntry",
            signpostID: OSSignpostID(interval.identifier),
            "run=%{public}@ operation=%{public}@ generation=%{public}lld batch=%{public}lld request=%{public}lld tick=%{public}lld scheduleDelayNs=%{public}lld",
            runIdentifier as NSString,
            interval.operation.rawValue as NSString,
            signed(context.generation),
            context.batchOrdinal ?? -1,
            context.requestOrdinal.map(Int64.init) ?? -1,
            signed(context.policyTick),
            signed(context.scheduleDelayNanoseconds)
        )
    }

    /// performance区間を結果付きsignpostで終了します。
    ///
    /// 責務: 1件の開始signpostを同じ匿名IDと完了結果で閉じます。
    /// - Parameters:
    ///   - interval: `begin`が返した同じ区間。
    ///   - outcome: 区間の完了結果。
    func end(
        _ interval: AcquisitionPerformanceInterval,
        outcome: AcquisitionPerformanceOutcome
    ) {
        emit(.end, interval: interval, outcome: outcome)
    }

    /// process内で重複しない次のinterval番号を返します。
    ///
    /// 責務: 並行する取得eventへlockで直列化した匿名番号を1件割り当てます。
    /// - Returns: 0を使用せずwrap時は1へ戻るprocess内番号。
    private func makeIdentifier() -> UInt64 {
        identifierLock.lock()
        defer { identifierLock.unlock() }
        let identifier = nextIdentifier
        nextIdentifier = nextIdentifier == UInt64.max ? 1 : nextIdentifier + 1
        return identifier
    }

    /// 操作に対応する開始または終了signpostを出力します。
    ///
    /// 責務: 1件のperformance区間を固定nameと匿名contextのOSLog eventへ変換します。
    /// - Parameters:
    ///   - type: 開始または終了signpost種別。
    ///   - interval: 出力する匿名区間。
    ///   - outcome: 終了時だけ含める完了結果。
    private func emit(
        _ type: OSSignpostType,
        interval: AcquisitionPerformanceInterval,
        outcome: AcquisitionPerformanceOutcome?
    ) {
        let context = interval.context
        os_signpost(
            type,
            log: log,
            name: signpostName(for: interval.operation),
            signpostID: OSSignpostID(interval.identifier),
            "run=%{public}@ generation=%{public}lld batch=%{public}lld request=%{public}lld tick=%{public}lld scheduleDelayNs=%{public}lld outcome=%{public}@",
            runIdentifier as NSString,
            signed(context.generation),
            context.batchOrdinal ?? -1,
            context.requestOrdinal.map(Int64.init) ?? -1,
            signed(context.policyTick),
            signed(context.scheduleDelayNanoseconds),
            (outcome?.rawValue ?? "began") as NSString
        )
    }

    /// operationを固定signpost nameへ変換します。
    ///
    /// 責務: 1件の取得操作をInstrumentsで安定分類できる静的nameへ写像します。
    /// - Parameter operation: 分類する取得操作。
    /// - Returns: 操作に固有の静的signpost name。
    private func signpostName(
        for operation: AcquisitionPerformanceOperation
    ) -> StaticString {
        switch operation {
        case .acquisitionStart: "AcquisitionStart"
        case .manifestPersistence: "ManifestPersistence"
        case .batchOpenPersistence: "BatchOpenPersistence"
        case .requestDispatchPersistence: "RequestDispatchPersistence"
        case .requestTransport: "RequestTransport"
        case .respondedPersistence: "RespondedPersistence"
        case .nonRespondedPersistence: "NonRespondedPersistence"
        case .batchSealPersistence: "BatchSealPersistence"
        case .batchAcquisition: "BatchAcquisition"
        case .staleBatchRejection: "StaleBatchRejection"
        case .generationCancellation: "GenerationCancellation"
        case .sessionTerminationPersistence: "SessionTerminationPersistence"
        case .terminationRecoveryPersistence: "TerminationRecoveryPersistence"
        }
    }

    /// 任意UIntを欠落sentinelと区別できる符号付き値へ変換します。
    ///
    /// 責務: signpost C引数用に任意の非負値をInt64へclampし、欠落を-1へ変換します。
    /// - Parameter value: 変換する任意UInt。
    /// - Returns: `nil`なら-1、それ以外はInt64範囲へclampした値。
    private func signed(_ value: UInt?) -> Int64 {
        value.map { Int64(clamping: $0) } ?? -1
    }

    /// 任意UInt64を欠落sentinelと区別できる符号付き値へ変換します。
    ///
    /// 責務: signpost C引数用に任意の非負値をInt64へclampし、欠落を-1へ変換します。
    /// - Parameter value: 変換する任意UInt64。
    /// - Returns: `nil`なら-1、それ以外はInt64範囲へclampした値。
    private func signed(_ value: UInt64?) -> Int64 {
        value.map { Int64(clamping: $0) } ?? -1
    }

    /// run識別子が匿名ASCII契約を満たすかを返します。
    ///
    /// 責務: 1件の外部run識別子を長さと許可byte集合だけで検証します。
    /// - Parameter runIdentifier: 検証する外部入力。
    /// - Returns: 1〜64 byteかつ英数字、`.`、`_`、`-`だけなら `true`。
    private static func isValid(runIdentifier: String) -> Bool {
        let bytes = Array(runIdentifier.utf8)
        guard (1...64).contains(bytes.count) else { return false }
        return bytes.allSatisfy { byte in
            (48...57).contains(byte)
                || (65...90).contains(byte)
                || (97...122).contains(byte)
                || byte == 45
                || byte == 46
                || byte == 95
        }
    }
}

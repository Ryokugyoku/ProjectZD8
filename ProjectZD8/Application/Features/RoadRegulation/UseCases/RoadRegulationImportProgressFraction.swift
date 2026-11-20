import Foundation

/// 取り込みの段階を、全体の進み具合(0...1)と段階の順番に直す型です(設計書 §3.7)。
///
/// | 段階 | 全体の進み具合 |
/// |---|---|
/// | 準備・一覧の取得 | 0 |
/// | ダウンロード | 受信バイト / 予定バイト × 0.4(予定が分からなければ `nil`) |
/// | 取り込み | 0.4 + 処理した圧縮バイト / 全圧縮バイト × 0.55(全体が 0 なら 0.4) |
/// | 有効化 | 0.95 |
/// | 掃除 | 0.975 |
///
/// 割合は 0...1 に切り詰め、各段階の割合はその段階の上限(ダウンロード 0.4、取り込み 0.95)を超えません。
/// そのため段階が進んだ時の割合は、前の段階の最後の割合より小さくなりません。
nonisolated struct RoadRegulationImportProgressFraction: Sendable {
    /// ダウンロードが全体に占める割合。
    static let downloadShare = 0.4
    /// 取り込みが全体に占める割合。
    static let importShare = 0.55
    /// ダウンロードの段階の上限(取り込みの段階の始まりと同じ値)。
    static let downloadEndFraction = downloadShare
    /// 取り込みの段階の上限(有効化の段階と同じ値。浮動小数の誤差で超えないように切り詰めます)。
    static let importEndFraction = 0.95
    /// 有効化の段階の進み具合。
    static let activatingFraction = importEndFraction
    /// 掃除の段階の進み具合。
    static let cleaningUpFraction = 0.975

    /// 状態を持たない計算器を作ります。
    ///
    /// 責務: 計算器を構築します。
    init() {}

    /// 段階から全体の進み具合を求めます。
    ///
    /// 責務: 段階ごとの式で、全体の進み具合を 0...1 で返します。
    /// - Parameter phase: 取り込みの段階。
    /// - Returns: 全体の進み具合。ダウンロードの予定バイトが分からなければ `nil`。
    func fraction(of phase: RoadRegulationImportPhase) -> Double? {
        switch phase {
        case .preparing, .fetchingCatalog:
            return 0
        case let .downloading(transfer):
            return downloadFraction(transfer)
        case let .importing(read, _):
            let ratio = Self.ratio(Double(read.processedCompressedBytes), Double(read.totalCompressedBytes))
            return min(Self.importEndFraction, Self.downloadEndFraction + ratio * Self.importShare)
        case .activating:
            return Self.activatingFraction
        case .cleaningUp:
            return Self.cleaningUpFraction
        }
    }

    /// 段階の順番(0 始まり)を返します。
    ///
    /// 責務: 進捗の値を除いた段階の種類を、比べられる番号にします。
    /// - Parameter phase: 取り込みの段階。
    /// - Returns: 準備 0、一覧 1、ダウンロード 2、取り込み 3、有効化 4、掃除 5。
    func stage(of phase: RoadRegulationImportPhase) -> Int {
        switch phase {
        case .preparing: 0
        case .fetchingCatalog: 1
        case .downloading: 2
        case .importing: 3
        case .activating: 4
        case .cleaningUp: 5
        }
    }

    /// ダウンロードの進み具合を全体の割合にします。
    ///
    /// 責務: 予定バイトが正の時だけ割合を求めます。
    /// - Parameter transfer: 受け取りの進み具合。
    /// - Returns: 全体の進み具合。予定バイトが無いか 0 以下なら `nil`。
    private func downloadFraction(_ transfer: RoadRegulationTransferProgress) -> Double? {
        guard let expected = transfer.expectedBytes, expected > 0 else { return nil }
        return min(Self.downloadEndFraction, Self.ratio(Double(transfer.receivedBytes), Double(expected)) * Self.downloadShare)
    }

    /// 分子 / 分母を 0...1 に切り詰めて返します。
    ///
    /// 責務: 0 除算と範囲外の値を防ぎます。
    /// - Parameters:
    ///   - numerator: 分子。
    ///   - denominator: 分母。
    /// - Returns: 0...1 の割合。分母が 0 以下なら 0。
    private static func ratio(_ numerator: Double, _ denominator: Double) -> Double {
        guard denominator > 0 else { return 0 }
        return min(1, max(0, numerator / denominator))
    }
}

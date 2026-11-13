import Foundation

/// 取得エンジンが購読者へ流す出来事です。
nonisolated enum AcquisitionEvent: Sendable {
    /// 記録を開始しました。
    case started(Start)
    /// 1ティックの取得と保存が完了しました。
    case tick(Tick)
    /// 記録を終了しました。終了状態に更新した最終のセッションを持ちます。
    case ended(DriveSession)

    /// 記録開始時の情報です。
    nonisolated struct Start: Sendable {
        /// 開始済みのセッションです。
        let session: DriveSession
        /// セッションに固定した取得条件です。
        let pids: [SessionPID]
        /// PID定義の参照に使った車種コードです。
        let vehicleModelCode: String?
    }

    /// 1ティック分の取得結果です。
    nonisolated struct Tick: Equatable, Sendable {
        /// 0始まりのティック番号です。
        let tick: Int
        /// セッション開始からの経過時間(マイクロ秒)です。
        let elapsedMicroseconds: Int64
        /// このティックで要求したPIDごとの解釈結果です。要求順に並びます。
        let readings: [TickReading]
        /// 開始からの記録済み要求の総数です。
        let sampleCount: Int
        /// 開始からのデータ付き応答の総数です。
        let respondedCount: Int
        /// 走行距離(km)です。距離計PIDが未取得なら `nil` です。
        let distanceKilometers: Double?

        /// データ付き応答の割合(0...1)です。要求が無ければ 0 です。
        var responseRate: Double { sampleCount == 0 ? 0 : Double(respondedCount) / Double(sampleCount) }
    }

    /// 1件のPID要求の解釈結果です。
    nonisolated struct TickReading: Equatable, Sendable {
        let request: OBDPIDRequest
        let reading: Reading
    }

    /// 応答の解釈結果です。無効な値を 0 などへ置き換えません。
    nonisolated enum Reading: Equatable, Sendable {
        /// 規格範囲内の有効な物理値です。
        case value(Double)
        /// 変換できましたが規格範囲を外れています。
        case outOfRange(Double)
        /// 応答バイトを変換できませんでした。
        case decodeFailed
        /// データ付き応答がありませんでした。
        case noResponse(SampleOutcome)
    }
}

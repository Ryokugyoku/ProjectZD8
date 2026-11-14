import Foundation

/// 接続履歴画面の車両名、取得端末、識別子などの文字列表示を返します。
///
/// iOS と macOS の履歴画面で共通に使う純粋な表示変換です。空文字列は未設定として扱います。
struct ConnectionHistorySessionTextFormatter {
    /// 車両名称を未確定状態も含めて返します。
    ///
    /// 責務: 1件のセッションを登録車両名または識別中の文言へ変換します。
    /// - Parameter session: 車両名称を求めるセッション。
    /// - Returns: 空でない登録車両名、または `history.vehicle.pending` の文言。
    func vehicleName(_ session: ConnectionSession) -> String {
        Self.nonEmpty(session.vehicle?.name) ?? String(localized: "history.vehicle.pending")
    }

    /// 車両グループの見出しに使う車両名称を返します。
    ///
    /// 責務: 1件の任意車両情報を登録車両名または未関連付けの文言へ変換します。
    /// - Parameter vehicle: 車両グループの車両情報。グループや車両が無い場合は `nil`。
    /// - Returns: 空でない登録車両名、または `history.vehicle.unassigned` の文言。
    func vehicleGroupName(_ vehicle: ConnectionSessionVehicle?) -> String {
        Self.nonEmpty(vehicle?.name) ?? String(localized: "history.vehicle.unassigned")
    }

    /// 車両グループの補助表示に使う車両代表識別値を返します。
    ///
    /// 責務: 1件の任意車両情報を表示すべき代表識別値の有無へ変換します。
    /// - Parameter vehicle: 車両グループの車両情報。
    /// - Returns: 空でない代表識別値。表示しない場合は `nil`。
    func vehicleIdentifier(_ vehicle: ConnectionSessionVehicle?) -> String? {
        Self.nonEmpty(vehicle?.displayIdentifier)
    }

    /// セッションIDを短縮表示へ変換します。
    ///
    /// 責務: 1件のセッションIDを先頭8文字の大文字表記へ変換します。
    /// - Parameter id: 短縮するセッションID。
    /// - Returns: 短縮UUID表記。
    func shortID(_ id: ConnectionSessionID) -> String {
        String(id.rawValue.uuidString.prefix(8)).uppercased()
    }

    /// セッションの取得元端末をプラットフォーム付き表示名へ変換します。
    ///
    /// 責務: 1件の任意取得元端末を一覧表示用文字列または旧履歴向け不明表示へ変換します。
    /// - Parameter session: 取得元端末を表示するセッション。
    /// - Returns: `端末名 (プラットフォーム)`、または `history.device.unknown` の文言。
    func acquisitionDeviceText(_ session: ConnectionSession) -> String {
        guard let device = session.acquisitionDevice else {
            return String(localized: "history.device.unknown")
        }
        return "\(device.name) (\(device.platform.rawValue))"
    }

    /// 車両グループ識別子をアクセシビリティ識別用文字列へ変換します。
    ///
    /// 責務: 1件の車両グループ識別子を安定したUI識別文字列へ変換します。
    /// - Parameter id: 変換する車両グループ識別子。
    /// - Returns: 登録車両UUIDまたは `unassigned`。
    func groupIdentifier(_ id: ConnectionHistoryVehicleGroupID) -> String {
        switch id {
        case let .registered(vehicleID): vehicleID.rawValue.uuidString
        case .unassigned: "unassigned"
        }
    }

    /// セッション行に表示する終了理由のローカライズキーを返します。
    ///
    /// 責務: 1件の任意終了理由を登録済み固定キーへ変換し、未終了時は全件条件のキーを使います。
    /// - Parameter reason: 表示する終了理由。
    /// - Returns: View 側で `LocalizedStringKey` に包むローカライズキー。
    func endReasonKey(_ reason: ConnectionSessionEndReason?) -> String {
        reason?.historyLocalizationKey ?? ConnectionHistoryEndReasonFilter.all.historyLocalizationKey
    }

    /// 空文字列を未設定として扱った表示可能文字列を返します。
    ///
    /// 責務: 1件の任意文字列を空なら `nil` へ正規化します。
    /// - Parameter value: 正規化する任意文字列。
    /// - Returns: 空でない文字列、または `nil`。
    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

#if os(iOS)
import CryptoKit
import Foundation

/// ExternalAccessoryフレームワークから取得した検出時点の不変値です。
nonisolated struct IOSExternalAccessorySnapshot: Equatable, Sendable {
    /// 現在のOSセッション内で割り当てられた接続識別値です。
    let connectionID: Int
    /// アクセサリーの表示名です。
    let name: String
    /// メーカー名です。
    let manufacturer: String
    /// 製品型番です。
    let modelNumber: String
    /// メーカーが割り当てたシリアル番号です。
    let serialNumber: String
    /// アクセサリーが公開するExternalAccessoryプロトコル文字列です。
    let protocolStrings: [String]
    /// iOSが接続済みとして報告したかどうかです。
    let isConnected: Bool

    /// ExternalAccessoryの検出値を副作用のないスナップショットへ固定します。
    ///
    /// 責務: 1件のExternalAccessory検出値を候補変換と再特定に必要な最小情報へまとめます。
    /// - Parameters:
    ///   - connectionID: 現在のOSセッション内で割り当てられた接続識別値。
    ///   - name: アクセサリーの表示名。
    ///   - manufacturer: メーカー名。
    ///   - modelNumber: 製品型番。
    ///   - serialNumber: メーカーが割り当てたシリアル番号。
    ///   - protocolStrings: アクセサリーが公開するプロトコル文字列。
    ///   - isConnected: iOSが接続済みとして報告したかどうか。
    init(
        connectionID: Int,
        name: String,
        manufacturer: String,
        modelNumber: String,
        serialNumber: String,
        protocolStrings: [String],
        isConnected: Bool
    ) {
        self.connectionID = connectionID
        self.name = name
        self.manufacturer = manufacturer
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.protocolStrings = protocolStrings
        self.isConnected = isConnected
    }
}

/// ExternalAccessory検出値をプライバシーを保ったDomain候補へ変換します。
nonisolated struct IOSExternalAccessorySnapshotMapper: Sendable {
    /// 許可済みプロトコルを持つ接続済みアクセサリーをBluetooth Classic候補へ変換します。
    ///
    /// 責務: 1件のExternalAccessoryスナップショットを選択可能なOBD接続候補へ写像します。
    /// - Parameters:
    ///   - snapshot: ExternalAccessoryから取得した検出値。
    ///   - configuration: メーカー確認済みプロトコル許可集合。
    /// - Returns: 接続済みかつプロトコル一致時の候補。それ以外は `nil`。
    func makeAdapter(
        from snapshot: IOSExternalAccessorySnapshot,
        configuration: IOSExternalAccessoryProtocolConfiguration
    ) -> DiscoveredAdapter? {
        guard snapshot.isConnected,
              configuration.matchingProtocol(in: snapshot.protocolStrings) != nil else {
            return nil
        }
        let identifier = systemIdentifier(for: snapshot)
        let displayName = normalized(snapshot.name)
            ?? normalized(snapshot.modelNumber)
            ?? "External Accessory"
        return DiscoveredAdapter(
            id: identifier,
            transportMode: .bluetooth,
            connectionTransport: .bluetoothClassic,
            displayName: displayName,
            manufacturerName: normalized(snapshot.manufacturer),
            productName: normalized(snapshot.modelNumber),
            systemIdentifier: identifier,
            serialNumber: nil,
            isConnected: true,
            connectionState: .connected
        )
    }

    /// アクセサリーを再特定できる非可逆識別子を生成します。
    ///
    /// 責務: シリアル番号を外部へ露出せず1件のExternalAccessoryへ安定識別子を割り当てます。
    /// - Parameter snapshot: 識別対象のExternalAccessory検出値。
    /// - Returns: `external-accessory:` 接頭辞を持つSHA-256識別子。
    func systemIdentifier(for snapshot: IOSExternalAccessorySnapshot) -> String {
        let stableComponent = normalized(snapshot.serialNumber)
            ?? "connection-\(snapshot.connectionID)"
        let source = [
            normalized(snapshot.manufacturer) ?? "",
            normalized(snapshot.modelNumber) ?? "",
            stableComponent
        ].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "external-accessory:\(digest)"
    }

    /// 空白だけのフレームワーク文字列を欠損値へ変換します。
    ///
    /// 責務: 1件のExternalAccessory文字列を表示と識別に安全な任意値へ正規化します。
    /// - Parameter value: フレームワークが返した文字列。
    /// - Returns: 前後空白を除いた非空文字列。空の場合は `nil`。
    private func normalized(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
#endif

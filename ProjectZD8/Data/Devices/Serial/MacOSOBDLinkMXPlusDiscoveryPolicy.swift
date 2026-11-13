#if os(macOS)
import Foundation

/// macOSが報告したBluetooth Classic機器をOBDLink MX+候補へ限定します。
struct MacOSOBDLinkMXPlusDiscoveryPolicy {
    /// Bluetooth機器の名称とペアリング状態をMX+接続候補として検証します。
    ///
    /// 責務: 1件のBluetooth機器情報をペアリング済みOBDLink MX+かどうかへ分類します。
    /// - Parameters:
    ///   - name: macOSが返したBluetooth機器名称。
    ///   - isPaired: macOSのペアリングが完了しているかどうか。
    /// - Returns: 公式MX+名称に一致し、かつペアリング済みの場合は `true`。
    func accepts(name: String, isPaired: Bool) -> Bool {
        guard isPaired else { return false }
        let normalizedName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return normalizedName == "OBDLINK MX+" || normalizedName.hasPrefix("OBDLINK MX+ ")
    }
}
#endif

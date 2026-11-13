import Foundation
import MachO
#if os(macOS)
import Security
#endif

/// CloudKitを使ってよい実行環境かどうかを判定します。合成ルートが同期の実装を選ぶために使います。
///
/// `CKContainer` はiCloudコンテナのエンタイトルメントが無いと生成時に異常終了するため、
/// 生成する前にこの判定を通します。
nonisolated enum CloudKitAvailability {
    /// 責務: XCTestの下で動いておらず、iCloudコンテナのエンタイトルメントを持つ時だけ `true` を返します。
    static func isCloudKitUsable(containerIdentifier: String = CloudKitSyncConfiguration.containerIdentifier) -> Bool {
        decide(isRunningTests: isRunningTests(), hasContainerEntitlement: hasContainerEntitlement(containerIdentifier))
    }

    /// 責務: 判定材料から結論を出します。
    static func decide(isRunningTests: Bool, hasContainerEntitlement: Bool) -> Bool {
        !isRunningTests && hasContainerEntitlement
    }

    /// 責務: XCTestのホストとして動いているかどうかを返します。
    static func isRunningTests(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// 責務: 実行中のアプリがiCloudコンテナのエンタイトルメントを持つかどうかを返します。
    ///
    /// - macOS: 署名から実際のエンタイトルメントを読みます。
    /// - iOSシミュレーター: リンカーが `__TEXT,__entitlements` に埋め込んだエンタイトルメントを読みます。
    /// - iOS実機: エンタイトルメント付きの署名が無いと起動できないため `true` です。
    static func hasContainerEntitlement(_ containerIdentifier: String) -> Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil),
              let identifiers = value as? [String] else { return false }
        return identifiers.contains(containerIdentifier)
        #elseif targetEnvironment(simulator)
        guard let plist = embeddedSimulatorEntitlements(),
              let identifiers = plist["com.apple.developer.icloud-container-identifiers"] as? [String] else { return false }
        return identifiers.contains(containerIdentifier)
        #else
        return true
        #endif
    }

    #if targetEnvironment(simulator)
    /// 責務: メイン実行ファイルに埋め込まれたシミュレーター用エンタイトルメントを読みます。
    private static func embeddedSimulatorEntitlements() -> [String: Any]? {
        guard let header = _dyld_get_image_header(0) else { return nil }
        var size: UInt = 0
        let pointer = header.withMemoryRebound(to: mach_header_64.self, capacity: 1) { header64 in
            getsectiondata(header64, "__TEXT", "__entitlements", &size)
        }
        guard let pointer, size > 0 else { return nil }
        let data = Data(bytes: pointer, count: Int(size))
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
    #endif
}

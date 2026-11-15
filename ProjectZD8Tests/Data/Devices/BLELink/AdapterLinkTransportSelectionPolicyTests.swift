import Foundation
import XCTest
@testable import ProjectZD8

/// `AdapterLinkTransportSelectionPolicy` が、リンクが `ready` で同じ BLE アダプターを対象にしている時だけ常駐リンクを選ぶことを検証します。
final class AdapterLinkTransportSelectionPolicyTests: XCTestCase {
    /// 検証対象の方針です。
    private let policy = AdapterLinkTransportSelectionPolicy()

    /// 常駐リンクの接続対象です。
    private static let target = UUID(uuidString: "6F1D2C3B-0000-4000-8000-00000000000A")!

    /// `ready` 以外の全リンク状態です。
    private static let nonReadyStates: [AdapterLinkState] = [
        .idle, .awaitingPeripheral, .connecting, .discovering,
        .disconnected(.peripheralDisconnected(errorDescription: nil)), .disconnected(.retryLimitExceeded),
    ]

    /// 終端を作ります。
    ///
    /// 責務: 指定の方式と識別子の終端を返します。
    /// - Parameters:
    ///   - identifier: システム識別子。
    ///   - transport: 通信方式。
    /// - Returns: 接続終端。
    private func endpoint(_ identifier: String, transport: OBDConnectionEndpoint.Transport = .bluetoothLowEnergy) -> OBDConnectionEndpoint {
        OBDConnectionEndpoint(transport: transport, systemIdentifier: identifier, displayName: "Adapter")
    }

    /// リンクが `ready` で、終端が同じアダプター(UUID の大文字小文字は問わない)なら常駐リンクを使います。
    ///
    /// 責務: 大文字・小文字の UUID 表記の両方で `true` になることを確認します。
    func testReadyLinkForSameAdapterUsesResidentLink() {
        for identifier in [Self.target.uuidString.uppercased(), Self.target.uuidString.lowercased()] {
            XCTAssertTrue(policy.usesResidentLink(for: endpoint(identifier), linkTargetIdentifier: Self.target, linkState: .ready), identifier)
        }
    }

    /// リンクが `ready` でなければフォールバックします。
    ///
    /// 責務: `ready` 以外の全状態で `false` になることを確認します。
    func testNonReadyLinkFallsBack() {
        for state in Self.nonReadyStates {
            XCTAssertFalse(
                policy.usesResidentLink(for: endpoint(Self.target.uuidString), linkTargetIdentifier: Self.target, linkState: state), "\(state)"
            )
        }
    }

    /// 別のアダプター・リンクの接続対象なし・UUID でない識別子ならフォールバックします。
    ///
    /// 責務: 対象の不一致と保持なしの各場合で `false` になることを確認します。
    func testOtherAdapterOrNoTargetFallsBack() {
        let other = endpoint("6F1D2C3B-0000-4000-8000-00000000000B")
        XCTAssertFalse(policy.usesResidentLink(for: other, linkTargetIdentifier: Self.target, linkState: .ready))
        XCTAssertFalse(policy.usesResidentLink(for: endpoint(Self.target.uuidString), linkTargetIdentifier: nil, linkState: .ready))
        XCTAssertFalse(policy.usesResidentLink(for: endpoint("not-a-uuid"), linkTargetIdentifier: Self.target, linkState: .ready))
        XCTAssertFalse(policy.usesResidentLink(for: endpoint(""), linkTargetIdentifier: Self.target, linkState: .ready))
    }

    /// BLE 以外(Classic・シリアル)の終端は、識別子が同じでもフォールバックします。
    ///
    /// 責務: 通信方式が違う終端で `false` になることを確認します。
    func testNonBLEEndpointFallsBack() {
        for transport in [OBDConnectionEndpoint.Transport.bluetoothClassic, .serial] {
            let candidate = endpoint(Self.target.uuidString, transport: transport)
            XCTAssertFalse(policy.usesResidentLink(for: candidate, linkTargetIdentifier: Self.target, linkState: .ready), "\(transport)")
        }
    }

    /// 常駐リンクを使える時は、常駐リンクだけを使うべきかどうかにかかわらず常駐リンクを選びます。
    ///
    /// 責務: `requiresResidentLink` の両方の値で `.residentLink` になることを確認します(U2 受け入れ条件 6)。
    func testSelectionUsesResidentLinkWhenUsable() {
        for requires in [true, false] {
            let selection = policy.selection(
                for: endpoint(Self.target.uuidString), linkTargetIdentifier: Self.target, linkState: .ready, requiresResidentLink: requires
            )
            XCTAssertEqual(selection, .residentLink, "\(requires)")
        }
    }

    /// 常駐リンクだけを使うべき BLE 終端で、常駐リンクを使えない時は接続しません(自前の接続へ落ちません)。
    ///
    /// 責務: リンクが `ready` でない全状態・接続対象なし・別のアダプター・UUID でない識別子のすべてで `.residentLinkUnavailable` になることを確認します(U2 受け入れ条件 6)。
    func testSelectionRefusesFallbackWhenResidentLinkRequiredButUnusable() {
        let target = endpoint(Self.target.uuidString)
        for state in Self.nonReadyStates {
            let selection = policy.selection(for: target, linkTargetIdentifier: Self.target, linkState: state, requiresResidentLink: true)
            XCTAssertEqual(selection, .residentLinkUnavailable, "\(state)")
        }
        let unusable: [(OBDConnectionEndpoint, UUID?)] = [
            (target, nil), (endpoint("6F1D2C3B-0000-4000-8000-00000000000B"), Self.target), (endpoint("not-a-uuid"), Self.target),
        ]
        for (candidate, linkTarget) in unusable {
            let selection = policy.selection(for: candidate, linkTargetIdentifier: linkTarget, linkState: .ready, requiresResidentLink: true)
            XCTAssertEqual(selection, .residentLinkUnavailable, "\(candidate.systemIdentifier)")
        }
    }

    /// 常駐リンクだけを使うべきでない時(手動接続など)は、常駐リンクを使えなければ従来どおり自前の接続です。
    ///
    /// 責務: リンクが `ready` でない・接続対象なしの時に `.fallback` になることを確認します(U2「変えないもの」)。
    func testSelectionFallsBackWhenResidentLinkNotRequired() {
        let target = endpoint(Self.target.uuidString)
        for state in Self.nonReadyStates {
            XCTAssertEqual(policy.selection(for: target, linkTargetIdentifier: Self.target, linkState: state, requiresResidentLink: false), .fallback, "\(state)")
        }
        XCTAssertEqual(policy.selection(for: target, linkTargetIdentifier: nil, linkState: .ready, requiresResidentLink: false), .fallback)
    }

    /// BLE 以外の終端は、常駐リンクだけを使うべき時でも従来どおり自前の接続です。
    ///
    /// 責務: Classic・シリアルの終端で、`requiresResidentLink` の両方の値で `.fallback` になることを確認します(U2「変えないもの」)。
    func testSelectionFallsBackForNonBLEEndpoint() {
        for transport in [OBDConnectionEndpoint.Transport.bluetoothClassic, .serial] {
            for requires in [true, false] {
                let candidate = endpoint(Self.target.uuidString, transport: transport)
                let selection = policy.selection(for: candidate, linkTargetIdentifier: Self.target, linkState: .ready, requiresResidentLink: requires)
                XCTAssertEqual(selection, .fallback, "\(transport) \(requires)")
            }
        }
    }
}

import Foundation
@testable import ProjectZD8

/// 位置の読み出しで必ず `ConnectionSessionRepositoryError.unavailable` を投げる、位置の Repository の偽物です。
nonisolated final class RoadRegulationFailingLocationRepository: ConnectionSessionLocationRepository, @unchecked Sendable {
    /// 責務: このテストでは使わない位置の追記を受け流します。
    func appendSample(_ fix: LocationFix, for sessionID: ConnectionSessionID) throws {}

    /// 責務: 位置の読み出しを失敗させます。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func samples(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionLocationSample] {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 責務: このテストでは使わない状態変化の追記を受け流します。
    func appendEvent(_ kind: ConnectionSessionLocationEventKind, occurredAt: Date, for sessionID: ConnectionSessionID) throws {}

    /// 責務: このテストでは使わない状態変化の読み出しに空配列を返します。
    func events(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionLocationEvent] { [] }
}

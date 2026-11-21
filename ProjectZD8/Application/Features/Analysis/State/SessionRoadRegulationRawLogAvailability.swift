import Foundation

/// 交通規制の照合を始める時の、車速の記録(Raw)の在りかです。
nonisolated enum SessionRoadRegulationRawLogAvailability: Equatable, Sendable {
    /// 端末にあります(解析の読み込みが `loaded`)。
    case onDevice
    /// 端末から退避済みで iCloud にあります(解析が `awaitingDownloadConfirmation`)。
    case inCloud
    /// 読めませんでした(解析の読み込みが `failed`)。
    case unreadable
}

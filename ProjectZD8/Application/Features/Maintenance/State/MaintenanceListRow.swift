import Foundation

/// 整備記録一覧の1行分です。
nonisolated struct MaintenanceListRow: Identifiable, Equatable, Sendable {
    /// 作業項目1件の要約です。
    struct WorkItemSummary: Identifiable, Equatable, Sendable {
        let id: UUID
        /// 部品の表示名キーです。
        let componentKey: String
        /// 作業種別の表示名キーです。
        let operationKey: String
        /// 製品名です。空なら未入力です。
        let productName: String
    }

    let id: MaintenanceRecordID
    let vehicleID: VehicleID
    let kind: MaintenanceKind
    /// 区分の表示名キーです。
    let kindKey: String
    let title: String
    let performedAt: Date
    /// 整備時点の走行距離(km)です。
    let odometerKilometers: Double?
    let notes: String
    let workItems: [WorkItemSummary]
    let photoCount: Int
    let fastenerGroupCount: Int

    /// 保存済みの記録から行を生成します。
    ///
    /// 責務: 整備記録を一覧表示用の値へ写します。
    init(record: MaintenanceRecord) {
        id = record.id
        vehicleID = record.vehicleID
        kind = record.kind
        kindKey = record.kind.localizationKey
        title = record.title
        performedAt = record.performedAt
        odometerKilometers = record.odometerKilometers
        notes = record.notes
        workItems = record.workItems.map {
            WorkItemSummary(id: $0.id, componentKey: $0.component.localizationKey, operationKey: $0.operation.localizationKey, productName: $0.productName)
        }
        photoCount = record.photos.count
        fastenerGroupCount = record.fastenerGroups.count
    }

    /// 走行距離の表示用文字列です。未入力なら `nil` です。
    var odometerText: String? {
        odometerKilometers.map {
            Measurement(value: $0, unit: UnitLength.kilometers)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
        }
    }
}

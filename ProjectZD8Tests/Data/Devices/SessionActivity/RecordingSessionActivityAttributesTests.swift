import Foundation
import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityAttributes` の定数と、`ContentState` の JSON の形(キー名・値の型)が配置換えの前後で変わらないことを検証します。
///
/// 仕様: U5 受け入れ条件 11・12(B14)。期待する JSON は、配置換え前(`b9a876c`)の定義
/// (`vehicle`・`statusKey`・`statusTone`・`vehicleSpeed`・`engineSpeed`・`throttlePosition`・`receivedResponseCount`・`startedAt`・
/// `vehiclePhotoFileName`、入れ子の enum は Swift の合成 Codable)から導いた形です。
final class RecordingSessionActivityAttributesTests: XCTestCase {
    /// 写真あり・名称あり・取得済みの値を持つ表示内容です。
    private let named = RecordingSessionActivityAttributes.ContentState(
        vehicle: .named("BRZ"),
        statusKey: "live_activity.status.recording",
        statusTone: .warning,
        vehicleSpeed: .value(42),
        engineSpeed: .unavailable,
        throttlePosition: .value(12.5),
        receivedResponseCount: 7,
        startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
        vehiclePhotoFileName: "p.jpg"
    )

    /// 写真なし・未登録・未取得の値を持つ表示内容です。
    private let unregistered = RecordingSessionActivityAttributes.ContentState(
        vehicle: .unregistered,
        statusKey: "live_activity.status.reading",
        statusTone: .normal,
        vehicleSpeed: .unavailable,
        engineSpeed: .value(800),
        throttlePosition: .unavailable,
        receivedResponseCount: 0,
        startedAt: Date(timeIntervalSinceReferenceDate: 0),
        vehiclePhotoFileName: nil
    )

    /// JSON を辞書として読みます。
    ///
    /// 責務: 比較のために JSON データを Foundation の辞書へ変換します。
    private func object(_ data: Data) throws -> NSDictionary {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    /// 配置換え前の形の JSON です(写真あり・名称あり)。
    private let namedJSON = """
        {"vehicle":{"named":{"_0":"BRZ"}},"statusKey":"live_activity.status.recording","statusTone":{"warning":{}},
        "vehicleSpeed":{"value":{"_0":42}},"engineSpeed":{"unavailable":{}},"throttlePosition":{"value":{"_0":12.5}},
        "receivedResponseCount":7,"startedAt":1000,"vehiclePhotoFileName":"p.jpg"}
        """

    /// 配置換え前の形の JSON です(写真なし・未登録)。
    private let unregisteredJSON = """
        {"vehicle":{"unregistered":{}},"statusKey":"live_activity.status.reading","statusTone":{"normal":{}},
        "vehicleSpeed":{"unavailable":{}},"engineSpeed":{"value":{"_0":800}},"throttlePosition":{"unavailable":{}},
        "receivedResponseCount":0,"startedAt":0}
        """

    /// エンコードした JSON のキー名と値の型が、配置換え前の形と同じです。
    ///
    /// 責務: 2つの表示内容のエンコード結果を、期待する JSON と辞書として比べます(写真名 `nil` はキー自体が無い)。
    func testEncodedJSONShapeIsUnchanged() throws {
        let encoder = JSONEncoder()
        XCTAssertEqual(try object(encoder.encode(named)), try object(Data(namedJSON.utf8)))
        XCTAssertEqual(try object(encoder.encode(unregistered)), try object(Data(unregisteredJSON.utf8)))
    }

    /// 配置換え前の形の JSON をデコードすると、同じ表示内容になります(往復も同じ)。
    ///
    /// 責務: 期待する JSON からのデコードと、エンコード→デコードの往復を確認します。
    func testDecodesPreviousShapeAndRoundTrips() throws {
        let decoder = JSONDecoder()
        typealias State = RecordingSessionActivityAttributes.ContentState
        XCTAssertEqual(try decoder.decode(State.self, from: Data(namedJSON.utf8)), named)
        XCTAssertEqual(try decoder.decode(State.self, from: Data(unregisteredJSON.utf8)), unregistered)
        XCTAssertEqual(try decoder.decode(State.self, from: JSONEncoder().encode(named)), named)
    }

    /// App Group・写真ディレクトリ・文言キーの定数は配置換え前と同じです。
    ///
    /// 責務: 5つの定数を配置換え前の値と比べます(受け入れ条件 13)。
    func testConstantsAreUnchanged() {
        XCTAssertEqual(RecordingSessionActivityAttributes.appGroupIdentifier, "group.Ryokugyoku.ProjectZD8")
        XCTAssertEqual(RecordingSessionActivityAttributes.vehiclePhotoDirectoryName, "SessionActivityVehiclePhotos")
        XCTAssertEqual(RecordingSessionActivityAttributes.unregisteredVehicleKey, "live_activity.vehicle.unregistered")
        XCTAssertEqual(RecordingSessionActivityAttributes.unavailableMetricKey, "live_activity.metric.unavailable")
        XCTAssertEqual(RecordingSessionActivityAttributes.stopButtonKey, "live_activity.action.stop")
    }

    /// 型名は ActivityKit の属性の識別に関わるため変えません。
    ///
    /// 責務: 属性と入れ子の型の名前を確認します(受け入れ条件 12)。
    func testTypeNamesAreUnchanged() {
        XCTAssertEqual(String(describing: RecordingSessionActivityAttributes.self), "RecordingSessionActivityAttributes")
        XCTAssertEqual(String(describing: RecordingSessionActivityAttributes.ContentState.self), "ContentState")
    }
}

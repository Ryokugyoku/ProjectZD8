import Foundation
import XCTest
@testable import ProjectZD8

/// 交通規制の照合のモデルを、ポートの Fake と、言語設定に依存しない部品で組み立て、期限つきの待ちを提供します。
///
/// 文字列は `localize` に決まった書式の表を注入して作ります(表に無いキーは `<キー>`)。時刻は Asia/Tokyo、数値は en_US_POSIX。
/// 待ちはすべて `LocationRecordingBoundedWaiter`(2秒。超えたら XCTFail)を使います。
@MainActor
final class SessionRoadRegulationReviewModelHarness {
    /// 数値の書式の地域です。
    nonisolated static let locale = Locale(identifier: "en_US_POSIX")
    /// 時刻の帯です。
    nonisolated static let timeZone = TimeZone(identifier: "Asia/Tokyo")!
    /// キーごとの書式です。表に無いキーは `<キー>` にします。
    nonisolated static let formats: [String: String] = [
        "analysis.road_regulation.figure.limit": "L=%@",
        "analysis.road_regulation.figure.maximum": "M=%@",
        "analysis.road_regulation.figure.minimum": "N=%@",
        "analysis.road_regulation.figure.exceeded_duration": "E=%@",
        "analysis.road_regulation.figure.wrong_way_distance": "W=%@",
        "analysis.road_regulation.figure.reference": "R=%@",
        "analysis.road_regulation.attribution.dataset": "%1$@ (%2$@)",
        "analysis.road_regulation.attribution.data_month": "%1$lld-%2$lld",
        "road_regulation.attribution.used_on": "U=%@",
    ]

    /// ポートの Fake です。
    let port = SessionRoadRegulationReviewPortFake()
    /// 既定のセッションです。
    let sessionID = ConnectionSessionID()
    /// 作った門です(`tearDown` で開けるため)。
    private var gates: [RoadRegulationTestGate] = []
    /// 検証対象のモデルです。
    private(set) lazy var model = SessionRoadRegulationReviewModel(
        reviewPort: port, contentBuilder: Self.makeContentBuilder(), sectionBuilder: SessionRoadRegulationReviewSectionBuilder(),
        overlayBuilder: SessionRoadRegulationReviewOverlayBuilder(highlightPaddingSeconds: 0.5, localize: { Self.localize($0) })
    )

    /// 部品を作ります。
    ///
    /// 責務: Fake を空の状態で用意します(モデルは最初の参照で作ります)。
    init() {}

    /// 現在の状態です。
    var state: SessionRoadRegulationReviewState {
        model.state
    }

    /// 責務: キーを書式の表で引き、無ければ `<キー>` を返します。
    nonisolated static func localize(_ key: String) -> String {
        formats[key] ?? "<\(key)>"
    }

    /// 責務: 地域・時刻の帯・文言を固定した内容の部品を作ります。
    private static func makeContentBuilder() -> SessionRoadRegulationReviewContentBuilder {
        let localize: @Sendable (String) -> String = { Self.localize($0) }
        let formatter = SessionRoadRegulationReviewRowFormatter(locale: locale, timeZone: timeZone, localize: localize)
        return SessionRoadRegulationReviewContentBuilder(
            rowBuilder: SessionRoadRegulationReviewRowBuilder(formatter: formatter),
            attributionBuilder: SessionRoadRegulationReviewAttributionBuilder(locale: locale, timeZone: timeZone, localize: localize)
        )
    }

    /// 責務: 動作を送ります。
    func send(_ action: SessionRoadRegulationReviewAction) {
        model.send(action)
    }

    /// 責務: 次の呼び出しの振る舞いを、呼び出しの順に積みます。
    /// - Parameters:
    ///   - result: 返す結果。
    ///   - held: 門で止めるか。
    ///   - ignoresCancellation: 取消に応じずに門の再開まで待つか。
    /// - Returns: 止める時はその門。
    @discardableResult
    func enqueue(
        _ result: Result<SessionRoadRegulationReviewResult, any Error>,
        held: Bool = false,
        ignoresCancellation: Bool = false
    ) -> RoadRegulationTestGate? {
        let gate = held ? RoadRegulationTestGate(isOpen: false) : nil
        if let gate { gates.append(gate) }
        port.responses.append(.init(result: result, gate: gate, ignoresCancellation: ignoresCancellation))
        return gate
    }

    /// 責務: 作ったすべての門を開け、止まった呼び出しを残しません。
    func openAllGates() {
        gates.forEach { $0.open() }
    }

    /// 責務: セッションの readiness を送ります(既定は `sessionID`)。
    func sendReadiness(_ readiness: SessionRoadRegulationReviewReadiness, session: ConnectionSessionID? = nil) {
        model.send(.readinessChanged(session ?? sessionID, readiness))
    }

    /// 責務: 照合結果を積み、`ready(raw)` を送り、loaded になるまで待ちます。
    /// - Parameters:
    ///   - review: 返す照合結果。
    ///   - raw: Raw の所在。
    ///   - session: セッション(既定は `sessionID`)。
    func load(
        _ review: SessionRoadRegulationReview = SessionRoadRegulationReviewModelTestValues.standardReview(),
        raw: SessionRoadRegulationRawLogAvailability = .onDevice,
        session: ConnectionSessionID? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let index = port.responses.count
        enqueue(.success(.reviewed(review)))
        sendReadiness(.ready(raw), session: session)
        await waitForCompletion(ofCall: index, file: file, line: line)
        await waitForStatus(.loaded, file: file, line: line)
    }

    /// 責務: status が指定の値になるまで期限つきで待ちます。
    func waitForStatus(_ status: SessionRoadRegulationReviewStatus, file: StaticString = #filePath, line: UInt = #line) async {
        await waitUntil("status \(status)", file: file, line: line) { self.state.status == status }
    }

    /// 責務: ポートの呼び出しが指定件数以上になるまで期限つきで待ちます。
    func waitForCalls(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        await waitUntil("calls \(count)", file: file, line: line) { self.port.calls.count >= count }
    }

    /// 責務: 門の前で呼び出しが待つまで期限つきで待ちます。
    func waitForWaiting(on gate: RoadRegulationTestGate?, file: StaticString = #filePath, line: UInt = #line) async {
        await waitUntil("gate waiting", file: file, line: line) { gate?.isWaiting == true }
    }

    /// 責務: 指定の番号の呼び出しが取消を受けるまで期限つきで待ちます。
    func waitForCancellation(ofCall index: Int, file: StaticString = #filePath, line: UInt = #line) async {
        await waitUntil("cancelled \(index)", file: file, line: line) { self.port.cancelledCalls.contains(index) }
    }

    /// 責務: 指定の番号の呼び出しが結果を返し終えるまで期限つきで待ちます。
    func waitForCompletion(ofCall index: Int, file: StaticString = #filePath, line: UInt = #line) async {
        await waitUntil("completed \(index)", file: file, line: line) { self.port.completedCalls.contains(index) }
    }

    /// 責務: 条件が成り立つまで期限(2秒)つきで待ち、成り立たなければテストを失敗させます。
    func waitUntil(_ description: String, file: StaticString = #filePath, line: UInt = #line, condition: () -> Bool) async {
        await LocationRecordingBoundedWaiter.waitUntil(description, file: file, line: line, condition: condition)
    }

    /// 責務: 起きてはいけない非同期処理が走り得る間だけ、他のタスクへ実行機会を渡します。
    func settle() async {
        await LocationRecordingBoundedWaiter.settle()
    }
}

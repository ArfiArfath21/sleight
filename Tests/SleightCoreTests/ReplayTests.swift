import XCTest
@testable import SleightCore

/// Replays real recordings (landmarks only, no images) through the engine.
final class ReplayTests: XCTestCase {
    func load(_ name: String) throws -> [RecordedFrame] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "jsonl"))
        return try RecordedFrame.load(jsonLines: Data(contentsOf: url))
    }

    /// An empty, dark room (brightness 11/255) where Vision reports hands in
    /// most frames. None of them may ever take control.
    func testGhostHandsInDarkRoomNeverEngage() throws {
        let frames = try load("dark-room-ghosts")
        XCTAssertGreaterThan(frames.filter { !$0.hands.isEmpty }.count, 50, "fixture should contain ghosts")
        let engine = SleightEngine()
        // Loop the clip for a full minute.
        var actions: [EngineAction] = []
        let duration = frames.last!.time - frames.first!.time + 1.0 / 30
        for loop in 0..<12 {
            for f in frames {
                let t = f.time + Double(loop) * duration
                actions += engine.process(FrameInput(time: t, hands: f.hands, aspect: f.aspect)).actions
            }
        }
        XCTAssertTrue(actions.isEmpty, "\(actions)")
    }
}

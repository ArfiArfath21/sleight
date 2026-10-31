import XCTest
@testable import SleightCore

final class PointerMotionTests: XCTestCase {
    func testCursorFollowsHand() {
        let sim = Sim()
        var h = sim.enterPointer()
        let start = sim.systemCursor
        sim.move(&h, by: Vec2(0.1, 0), over: 0.5)
        XCTAssertGreaterThan(sim.systemCursor.x - start.x, 50)
        sim.move(&h, by: Vec2(0, -0.08), over: 0.5)
        XCTAssertLessThan(sim.systemCursor.y, start.y - 30)
    }

    func testSlowIsPreciseFastCoversGround() {
        func pointsPerHand(speed: Double) -> Double {
            let sim = Sim()
            var h = sim.enterPointer()
            sim.hold(h, for: 0.3)
            let start = sim.systemCursor
            sim.move(&h, by: Vec2(0.5 * h.scale, 0), over: 0.5 / speed)
            sim.hold(h, for: 0.3)
            return (sim.systemCursor.x - start.x) / 0.5
        }
        let slow = pointsPerHand(speed: 0.2), medium = pointsPerHand(speed: 1.5), fast = pointsPerHand(speed: 5)
        XCTAssertLessThan(slow, 140)
        XCTAssertGreaterThan(medium, slow * 2)
        XCTAssertGreaterThan(fast, medium * 1.8)
    }

    func testJitterDoesNotLeakIntoCursor() {
        let sim = Sim()
        let h = sim.enterPointer()
        sim.noise = 0.0025
        sim.hold(h, for: 0.3)
        let start = sim.systemCursor
        var worst = 0.0
        for _ in 0..<60 { sim.step(h); worst = max(worst, distance(sim.systemCursor, start)) }
        XCTAssertLessThan(worst, 6)
    }
}

final class PointerClickTests: XCTestCase {
    func testClickLandsWhereAimed() {
        let sim = Sim()
        var h = sim.enterPointer()
        sim.move(&h, by: Vec2(0.05, 0.02), over: 0.4)
        sim.hold(h, for: 0.3)
        let aim = sim.systemCursor
        sim.clear()
        sim.pinch(&h, over: 0.12, drift: Vec2(0, 0.012))
        sim.hold(h, for: 0.1)
        sim.unpinch(&h)
        XCTAssertEqual(sim.downs.count, 1)
        XCTAssertEqual(sim.ups.count, 1)
        XCTAssertLessThan(distance(sim.downs[0].1, aim), 1.5)
        XCTAssertLessThan(distance(sim.ups[0].1, aim), 1.5)
        XCTAssertTrue(sim.media.isEmpty, "no play/pause in pointer mode")
    }

    func testDoubleClick() {
        let sim = Sim()
        var h = sim.enterPointer()
        sim.clear()
        sim.pinch(&h, over: 0.07); sim.unpinch(&h, over: 0.07)
        sim.hold(h, for: 0.07)
        sim.pinch(&h, over: 0.07); sim.unpinch(&h, over: 0.07)
        XCTAssertEqual(sim.downs.map(\.2), [1, 2])
    }

    func testDrag() {
        let sim = Sim()
        var h = sim.enterPointer()
        sim.clear()
        sim.pinch(&h)
        let at = sim.systemCursor
        sim.move(&h, by: Vec2(0.08, 0), over: 0.4)
        XCTAssertEqual(sim.lastHUD.pointer, .dragging)
        sim.unpinch(&h)
        XCTAssertGreaterThan(sim.ups[0].1.x - at.x, 40)
    }

    func testRightClick() {
        let sim = Sim()
        var h = sim.enterPointer()
        sim.clear()
        sim.move(&h, by: .zero, over: 0.1) { hand, f in hand.middlePinch = f }
        sim.hold(h, for: 0.1)
        sim.move(&h, by: .zero, over: 0.1) { hand, f in hand.middlePinch = 1 - f }
        sim.hold(h, for: 0.1)
        XCTAssertEqual(sim.downs.map(\.0), [.right])
        XCTAssertEqual(sim.ups.map(\.0), [.right])
    }

    func testTwoFingerFlickScrollsWithoutMovingCursor() {
        let sim = Sim()
        let h = sim.enterPointer()
        var v = SyntheticHand.vee(at: h.wrist)
        sim.hold(v, for: 0.3)
        let before = sim.systemCursor
        sim.move(&v, by: Vec2(0, -0.15), over: 0.15)
        sim.hold(v, for: 0.2)
        XCTAssertEqual(sim.flicks.count, 1)
        XCTAssertLessThan(distance(sim.systemCursor, before), 4)
    }
}

final class PointerExitTests: XCTestCase {
    func testFistExitsWithoutMovingCursorOrTriggeringCommands() {
        let sim = Sim()
        var h = sim.enterPointer()
        sim.hold(h, for: 0.2)
        let before = sim.systemCursor
        sim.move(&h, by: Vec2(0, 0.01), over: 0.12) { hand, f in hand.fingers = hand.fingers.map { _ in 1 - f } }
        sim.hold(h, for: 0.5)
        XCTAssertEqual(sim.mode, .command)
        XCTAssertEqual(sim.modes.last?.1, .gesture)
        XCTAssertLessThan(distance(sim.systemCursor, before), 3)
        // Opening the hand again right away must not swipe or scroll.
        sim.clear()
        var open = SyntheticHand.openPalm(at: h.wrist)
        sim.move(&open, by: Vec2(0.2, 0), over: 0.15)
        XCTAssertTrue(sim.effects.isEmpty)
    }

    func testLosingHandReleasesDragThenExits() {
        let sim = Sim()
        var h = sim.enterPointer()
        sim.pinch(&h)
        XCTAssertEqual(sim.downs.count, 1)
        sim.empty(for: 0.5)
        XCTAssertEqual(sim.ups.count, 1, "never leave a button stuck")
        XCTAssertEqual(sim.mode, .pointer, "short loss keeps the mode")
        sim.empty(for: 1.2)
        XCTAssertEqual(sim.mode, .command)
        XCTAssertEqual(sim.modes.last?.1, .lost)
    }

    func testShortDropoutIsBridged() {
        let sim = Sim()
        let h = sim.enterPointer()
        sim.hold(h, for: 0.2)
        let before = sim.systemCursor
        sim.empty(for: 0.15)
        XCTAssertEqual(sim.lastHUD.pointer, .lost)
        sim.hold(h, for: 0.3)
        XCTAssertEqual(sim.mode, .pointer)
        XCTAssertLessThan(distance(sim.systemCursor, before), 2)
    }

    func testDroppingHandExits() {
        let sim = Sim()
        var h = sim.enterPointer()
        sim.move(&h, to: Vec2(0.65, 1.2), over: 0.25)
        sim.hold(h, for: 0.4)
        XCTAssertEqual(sim.mode, .command)
    }

    func testBackOfHandExits() {
        let sim = Sim()
        var h = sim.enterPointer()
        h.flipped = true
        sim.hold(h, for: 0.6)
        XCTAssertEqual(sim.mode, .command)
        XCTAssertEqual(sim.modes.last?.1, .flipped)
    }

    func testTouchingTrackpadExits() {
        let sim = Sim()
        let h = sim.enterPointer()
        sim.lastRealInput = sim.time
        sim.step(h)
        XCTAssertEqual(sim.mode, .command)
        XCTAssertEqual(sim.modes.last?.1, .userInput)
    }
}

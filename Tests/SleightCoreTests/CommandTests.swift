import XCTest
@testable import SleightCore

final class ScrollFlickTests: XCTestCase {
    func testTwoFingerFlickUpScrollsContentUp() {
        let sim = Sim()
        var v = SyntheticHand.vee(at: Vec2(0.65, 0.65))
        sim.hold(v, for: 0.3)
        sim.move(&v, by: Vec2(0, -0.15), over: 0.15)
        sim.hold(v, for: 0.3)
        XCTAssertEqual(sim.flicks.count, 1)
        XCTAssertLessThan(sim.flicks[0].y, -800, "natural: flick up = content up = negative wheel")
        XCTAssertEqual(sim.flicks[0].x, 0)
    }

    func testFlickDownScrollsBack() {
        let sim = Sim()
        var v = SyntheticHand.vee(at: Vec2(0.65, 0.5))
        sim.hold(v, for: 0.3)
        sim.move(&v, by: Vec2(0, 0.15), over: 0.15)
        sim.hold(v, for: 0.2)
        XCTAssertEqual(sim.flicks.count, 1)
        XCTAssertGreaterThan(sim.flicks[0].y, 800)
    }

    func testFasterFlickScrollsFurther() {
        func velocity(over seconds: Double) -> Double {
            let sim = Sim()
            var v = SyntheticHand.vee(at: Vec2(0.65, 0.7))
            sim.hold(v, for: 0.3)
            sim.move(&v, by: Vec2(0, -0.2), over: seconds)
            sim.hold(v, for: 0.2)
            return abs(sim.flicks.first?.y ?? 0)
        }
        XCTAssertGreaterThan(velocity(over: 0.1), velocity(over: 0.25) * 1.3)
    }

    func testRepeatedFlicksWithSlowReturnKeepScrolling() {
        let sim = Sim()
        var v = SyntheticHand.vee(at: Vec2(0.65, 0.7))
        sim.hold(v, for: 0.3)
        for _ in 0..<3 {
            sim.move(&v, by: Vec2(0, -0.15), over: 0.13)  // flick up
            sim.move(&v, by: Vec2(0, 0.15), over: 0.6)    // slow return
            sim.hold(v, for: 0.1)
        }
        XCTAssertEqual(sim.flicks.count, 3)
        XCTAssertTrue(sim.flicks.allSatisfy { $0.y < 0 }, "return strokes must never scroll back")
    }

    func testQuickReturnStrokeIsIgnored() {
        let sim = Sim()
        var v = SyntheticHand.vee(at: Vec2(0.65, 0.7))
        sim.hold(v, for: 0.3)
        sim.move(&v, by: Vec2(0, -0.15), over: 0.13)
        sim.move(&v, by: Vec2(0, 0.15), over: 0.15)  // snapping back fast
        sim.hold(v, for: 0.3)
        XCTAssertEqual(sim.flicks.count, 1)
    }

    func testSlowTwoFingerDriftDoesNothing() {
        let sim = Sim()
        var v = SyntheticHand.vee(at: Vec2(0.65, 0.7))
        sim.hold(v, for: 0.3)
        sim.move(&v, by: Vec2(0, -0.2), over: 1.2)
        sim.move(&v, by: Vec2(0.2, 0), over: 1.2)
        XCTAssertTrue(sim.effects.isEmpty)
        XCTAssertEqual(sim.lastHUD.cue, .scroll)
    }

    func testTwoFingerSideFlickIsBackForward() {
        let sim = Sim()
        var v = SyntheticHand.vee(at: Vec2(0.65, 0.65))
        sim.hold(v, for: 0.3)
        sim.move(&v, by: Vec2(0.25, 0), over: 0.15)
        sim.hold(v, for: 0.8)
        sim.move(&v, by: Vec2(-0.25, 0), over: 0.15)
        sim.hold(v, for: 0.2)
        XCTAssertEqual(sim.shortcuts, [.back, .forward])
    }
}

final class SwipeTests: XCTestCase {
    func testOpenHandSwipes() {
        for (delta, expected) in [(Vec2(0.25, 0), Shortcut.spaceLeft),
                                  (Vec2(-0.25, 0), .spaceRight),
                                  (Vec2(0, -0.25), .missionControl)] {
            let sim = Sim()
            var h = SyntheticHand.openPalm(at: Vec2(0.65, 0.7))
            sim.hold(h, for: 0.3)
            sim.move(&h, by: delta, over: 0.15)
            sim.hold(h, for: 0.3)
            XCTAssertEqual(sim.shortcuts, [expected], "\(delta)")
        }
    }

    func testSwipeDownIsOffByDefault() {
        let sim = Sim()
        var h = SyntheticHand.openPalm(at: Vec2(0.65, 0.4))
        sim.hold(h, for: 0.3)
        sim.move(&h, by: Vec2(0, 0.25), over: 0.15)
        sim.hold(h, for: 0.3)
        XCTAssertTrue(sim.shortcuts.isEmpty)
    }

    func testHandSwingingIntoViewIsNotASwipe() {
        let sim = Sim()
        var h = SyntheticHand.openPalm(at: Vec2(0.0, 0.6))
        sim.move(&h, by: Vec2(0.5, 0), over: 0.15)
        sim.hold(h, for: 0.5)
        XCTAssertTrue(sim.shortcuts.isEmpty)
    }

    func testOneLongSweepIsOneSwipe() {
        let sim = Sim()
        var h = SyntheticHand.openPalm(at: Vec2(0.2, 0.6))
        sim.hold(h, for: 0.3)
        sim.move(&h, by: Vec2(0.9, 0), over: 0.6)
        sim.hold(h, for: 0.3)
        XCTAssertEqual(sim.shortcuts, [.spaceLeft])
    }

    func testRestingHandsOnKeyboardAreIgnored() {
        let sim = Sim()
        var v = SyntheticHand.vee(at: Vec2(0.65, 1.08))   // low in the frame
        sim.hold(v, for: 0.3)
        sim.move(&v, by: Vec2(0, -0.04), over: 0.1)
        var h = SyntheticHand.openPalm(at: Vec2(0.5, 1.08))
        sim.hold(h, for: 0.3)
        sim.move(&h, by: Vec2(0.3, 0), over: 0.15)
        XCTAssertTrue(sim.effects.isEmpty)
    }
}

final class PinchSliderTests: XCTestCase {
    func testPinchTapPlaysOrPauses() {
        let sim = Sim()
        var h = SyntheticHand.relaxed(at: Vec2(0.65, 0.65))
        sim.hold(h, for: 0.3)
        sim.pinch(&h)
        sim.unpinch(&h)
        sim.hold(h, for: 0.2)
        XCTAssertEqual(sim.media, [.playPause])
        XCTAssertTrue(sim.switcher.isEmpty)
    }

    func testLongPinchWithoutSlidingDoesNothing() {
        let sim = Sim()
        var h = SyntheticHand.relaxed(at: Vec2(0.65, 0.65))
        sim.hold(h, for: 0.3)
        sim.pinch(&h)
        sim.hold(h, for: 1.0)
        sim.unpinch(&h)
        XCTAssertTrue(sim.effects.isEmpty)
    }

    func testPinchSlideSidewaysDrivesAppSwitcher() {
        let sim = Sim()
        var h = SyntheticHand.relaxed(at: Vec2(0.45, 0.65))
        sim.hold(h, for: 0.3)
        sim.pinch(&h)
        sim.move(&h, by: Vec2(0.25, 0), over: 0.5)
        sim.hold(h, for: 0.2)
        sim.unpinch(&h)
        XCTAssertEqual(sim.switcher, [.begin, .next, .next, .commit])
        XCTAssertTrue(sim.media.isEmpty, "sliding is not a tap")
    }

    func testSlidingBackStepsBackwards() {
        let sim = Sim()
        var h = SyntheticHand.relaxed(at: Vec2(0.45, 0.65))
        sim.hold(h, for: 0.3)
        sim.pinch(&h)
        sim.move(&h, by: Vec2(0.2, 0), over: 0.4)
        sim.move(&h, by: Vec2(-0.12, 0), over: 0.4)
        sim.unpinch(&h)
        XCTAssertEqual(sim.switcher.first, .begin)
        XCTAssertTrue(sim.switcher.contains(.previous), "\(sim.switcher)")
        XCTAssertEqual(sim.switcher.last, .commit)
    }

    func testPinchSlideVerticalChangesVolume() {
        let sim = Sim()
        var h = SyntheticHand.relaxed(at: Vec2(0.65, 0.75))
        sim.hold(h, for: 0.3)
        sim.pinch(&h)
        sim.move(&h, by: Vec2(0, -0.15), over: 0.5)
        sim.unpinch(&h)
        XCTAssertGreaterThanOrEqual(sim.media.filter { $0 == .volumeUp }.count, 3)
        XCTAssertFalse(sim.media.contains(.playPause))
        sim.clear()
        sim.hold(h, for: 0.3)
        sim.pinch(&h)
        sim.move(&h, by: Vec2(0, 0.1), over: 0.4)
        sim.unpinch(&h)
        XCTAssertTrue(sim.media.allSatisfy { $0 == .volumeDown })
        XCTAssertGreaterThanOrEqual(sim.media.count, 2)
    }

    func testLosingTheHandMidSwitchCancelsSafely() {
        let sim = Sim()
        var h = SyntheticHand.relaxed(at: Vec2(0.45, 0.65))
        sim.hold(h, for: 0.3)
        sim.pinch(&h)
        sim.move(&h, by: Vec2(0.15, 0), over: 0.3)
        sim.empty(for: 0.6)
        XCTAssertEqual(sim.switcher.first, .begin)
        XCTAssertEqual(sim.switcher.last, .cancel, "⌘ must never be left held down")
    }

    func testTypingCancelsSwitcher() {
        let sim = Sim()
        var h = SyntheticHand.relaxed(at: Vec2(0.45, 0.65))
        sim.hold(h, for: 0.3)
        sim.pinch(&h)
        sim.move(&h, by: Vec2(0.15, 0), over: 0.3)
        sim.lastRealInput = sim.time
        sim.step(h)
        XCTAssertEqual(sim.switcher.last, .cancel)
    }
}

final class ModeTests: XCTestCase {
    func testHoldingAPointEntersPointerMode() {
        let sim = Sim()
        let p = SyntheticHand.point(at: Vec2(0.65, 0.6))
        sim.hold(p, for: 0.3)
        XCTAssertEqual(sim.mode, .command)
        XCTAssertEqual(sim.lastHUD.cue, .point)
        XCTAssertGreaterThan(sim.lastHUD.progress, 0.3)
        sim.hold(p, for: 0.4)
        XCTAssertEqual(sim.mode, .pointer)
        XCTAssertEqual(sim.modes.first?.0, .pointer)
    }

    func testPointingWhileMovingDoesNotEnterPointerMode() {
        let sim = Sim()
        var p = SyntheticHand.point(at: Vec2(0.3, 0.6))
        sim.move(&p, by: Vec2(0.6, 0), over: 1.5)  // ~2.5 hs/s
        XCTAssertEqual(sim.mode, .command)
    }

    func testManualModeSwitch() {
        let sim = Sim()
        _ = sim.engine.setMode(.pointer, systemCursor: Vec2(10, 10), time: sim.time)
        XCTAssertEqual(sim.mode, .pointer)
        var h = SyntheticHand.relaxed(at: Vec2(0.65, 0.6))
        sim.hold(h, for: 0.3)
        sim.move(&h, by: Vec2(0.05, 0), over: 0.3)
        XCTAssertGreaterThan(sim.systemCursor.x, 20, "pointer mode adopts the hand in view")
    }
}

final class TwoHandTests: XCTestCase {
    func testSpreadingTwoOpenHandsZoomsIn() {
        let sim = Sim()
        var l = SyntheticHand.openPalm(at: Vec2(0.5, 0.65))
        var r = SyntheticHand.openPalm(at: Vec2(0.8, 0.65))
        l.chirality = .left
        sim.hold([l, r], for: 0.3)
        for i in 1...12 {
            let f = Double(i) / 12
            l.wrist = Vec2(0.5 - 0.25 * f, 0.65)
            r.wrist = Vec2(0.8 + 0.25 * f, 0.65)
            sim.step([l, r])
        }
        sim.hold([l, r], for: 0.2)
        XCTAssertFalse(sim.shortcuts.isEmpty)
        XCTAssertTrue(sim.shortcuts.allSatisfy { $0 == .zoomIn }, "\(sim.shortcuts)")
    }

    func testSqueezingZoomsOut() {
        let sim = Sim()
        var l = SyntheticHand.openPalm(at: Vec2(0.25, 0.65))
        var r = SyntheticHand.openPalm(at: Vec2(1.05, 0.65))
        sim.hold([l, r], for: 0.3)
        for i in 1...12 {
            let f = Double(i) / 12
            l.wrist = Vec2(0.25 + 0.2 * f, 0.65)
            r.wrist = Vec2(1.05 - 0.2 * f, 0.65)
            sim.step([l, r])
        }
        XCTAssertFalse(sim.shortcuts.isEmpty)
        XCTAssertTrue(sim.shortcuts.allSatisfy { $0 == .zoomOut })
    }

    func testSecondHandDoesNotStealAGestureInProgress() {
        let sim = Sim()
        var h = SyntheticHand.relaxed(at: Vec2(0.45, 0.65))
        let idle = SyntheticHand.fist(at: Vec2(1.1, 0.7))
        sim.hold([h, idle], for: 0.3)
        sim.move(&h, by: .zero, over: 0.1) { hand, f in hand.pinch = f; hand.fingers[0] = lerp(1, 0.6, f) }
        for i in 1...15 {
            h.wrist = Vec2(0.45 + 0.25 * Double(i) / 15, 0.65)
            sim.step([h, idle])
        }
        sim.move(&h, by: .zero, over: 0.1) { hand, f in hand.pinch = 1 - f; hand.fingers[0] = lerp(0.6, 1, f) }
        XCTAssertEqual(sim.switcher.first, .begin)
        XCTAssertEqual(sim.switcher.last, .commit)
    }
}

final class SafetyTests: XCTestCase {
    func testTypingSuppressesEverything() {
        let sim = Sim()
        var v = SyntheticHand.vee(at: Vec2(0.65, 0.65))
        sim.hold(v, for: 0.3)
        sim.lastRealInput = sim.time
        sim.move(&v, by: Vec2(0, -0.15), over: 0.15)
        XCTAssertTrue(sim.flicks.isEmpty)
    }

    func testFistsAndRandomShapesDoNothing() {
        let sim = Sim()
        var f = SyntheticHand.fist(at: Vec2(0.65, 0.6))
        sim.hold(f, for: 0.3)
        sim.move(&f, by: Vec2(0.3, -0.2), over: 0.15)
        var o = SyntheticHand.openPalm(at: Vec2(0.65, 0.6))
        o.fingers = [1, 0, 0, 1]
        sim.hold(o, for: 0.3)
        sim.move(&o, by: Vec2(-0.3, 0), over: 0.15)
        XCTAssertTrue(sim.effects.isEmpty)
    }

    func testNoisyStillHandsTriggerNothing() {
        let sim = Sim()
        sim.noise = 0.004
        for shape in [SyntheticHand.openPalm(at: Vec2(0.65, 0.6)), .vee(at: Vec2(0.65, 0.6)), .relaxed(at: Vec2(0.65, 0.6))] {
            sim.hold(shape, for: 2.0)
        }
        XCTAssertTrue(sim.effects.isEmpty, "\(sim.effects)")
    }
}

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

final class MediaRemoteTests: XCTestCase {
    func testPinchTapPlaysOrPauses() {
        let sim = Sim()
        var h = SyntheticHand.relaxed(at: Vec2(0.65, 0.65))
        sim.hold(h, for: 0.3)
        sim.pinch(&h)
        sim.unpinch(&h)
        sim.hold(h, for: 0.2)
        XCTAssertEqual(sim.media, [.playPause])
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

    func testPinchSlideSidewaysSkipsOneTrack() {
        let sim = Sim()
        var h = SyntheticHand.relaxed(at: Vec2(0.45, 0.65))
        sim.hold(h, for: 0.3)
        sim.pinch(&h)
        sim.move(&h, by: Vec2(0.25, 0), over: 0.4)
        sim.unpinch(&h)
        XCTAssertEqual(sim.media, [.next])
        sim.clear()
        sim.hold(h, for: 0.3)
        sim.pinch(&h)
        sim.move(&h, by: Vec2(-0.25, 0), over: 0.4)
        sim.unpinch(&h)
        XCTAssertEqual(sim.media, [.previous])
        XCTAssertTrue(sim.switcher.isEmpty, "media and apps are separate families")
    }
}

final class GrabSwitcherTests: XCTestCase {
    func grab(_ sim: Sim, _ h: inout SyntheticHand) {
        sim.move(&h, by: .zero, over: 0.12) { hand, f in hand.fingers = hand.fingers.map { _ in 1 - f } }
        sim.hold(h, for: 0.2)
    }

    func release(_ sim: Sim, _ h: inout SyntheticHand) {
        sim.move(&h, by: .zero, over: 0.12) { hand, f in hand.fingers = hand.fingers.map { _ in f } }
        sim.hold(h, for: 0.1)
    }

    func testGrabSlideReleaseSwitchesApps() {
        let sim = Sim()
        var h = SyntheticHand.openPalm(at: Vec2(0.4, 0.65))
        sim.hold(h, for: 0.3)
        grab(sim, &h)
        sim.move(&h, by: Vec2(0.3, 0), over: 0.6)
        release(sim, &h)
        XCTAssertEqual(sim.switcher.first, .begin)
        XCTAssertTrue(sim.switcher.contains(.next))
        XCTAssertEqual(sim.switcher.last, .commit)
        XCTAssertTrue(sim.shortcuts.isEmpty, "opening the hand must not also swipe")
    }

    func testSlidingBackStepsBackwards() {
        let sim = Sim()
        var h = SyntheticHand.openPalm(at: Vec2(0.4, 0.65))
        sim.hold(h, for: 0.3)
        grab(sim, &h)
        sim.move(&h, by: Vec2(0.25, 0), over: 0.5)
        sim.move(&h, by: Vec2(-0.12, 0), over: 0.4)
        release(sim, &h)
        XCTAssertTrue(sim.switcher.contains(.previous), "\(sim.switcher)")
        XCTAssertEqual(sim.switcher.last, .commit)
    }

    func testFistWithoutSlidingDoesNothing() {
        let sim = Sim()
        var h = SyntheticHand.openPalm(at: Vec2(0.5, 0.65))
        sim.hold(h, for: 0.3)
        grab(sim, &h)
        sim.hold(h, for: 1.0)
        release(sim, &h)
        XCTAssertTrue(sim.effects.isEmpty)
    }

    func testLosingTheHandMidSwitchCancels() {
        let sim = Sim()
        var h = SyntheticHand.openPalm(at: Vec2(0.4, 0.65))
        sim.hold(h, for: 0.3)
        grab(sim, &h)
        sim.move(&h, by: Vec2(0.2, 0), over: 0.4)
        sim.empty(for: 0.6)
        XCTAssertEqual(sim.switcher.first, .begin)
        XCTAssertEqual(sim.switcher.last, .cancel, "⌘ must never be left held down")
    }

    func testTypingCancelsSwitcher() {
        let sim = Sim()
        var h = SyntheticHand.openPalm(at: Vec2(0.4, 0.65))
        sim.hold(h, for: 0.3)
        grab(sim, &h)
        sim.move(&h, by: Vec2(0.2, 0), over: 0.4)
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

/// Two hands moving together and apart, frame by frame.
private func twoHands(_ sim: Sim, _ l: inout SyntheticHand, _ r: inout SyntheticHand,
                      to lx: Double, _ rx: Double, over seconds: Double, dropAtEnd: Bool = false) {
    let l0 = l.wrist.x, r0 = r.wrist.x
    let n = max(Int((seconds * sim.fps).rounded()), 1)
    for i in 1...n {
        let f = Double(i) / Double(n)
        l.wrist.x = lerp(l0, lx, f)
        r.wrist.x = lerp(r0, rx, f)
        sim.step(dropAtEnd && i == n ? [l] : [l, r])
    }
}

final class ClapTests: XCTestCase {
    func clap(_ sim: Sim, _ l: inout SyntheticHand, _ r: inout SyntheticHand, merge: Bool = false) {
        twoHands(sim, &l, &r, to: 0.6, 0.72, over: 0.1, dropAtEnd: merge)   // rush together
        if merge { sim.hold([l], for: 0.07) }
        twoHands(sim, &l, &r, to: 0.35, 0.97, over: 0.17)                 // apart again
    }

    func hands() -> (SyntheticHand, SyntheticHand) {
        var l = SyntheticHand.openPalm(at: Vec2(0.35, 0.65))
        l.chirality = .left
        return (l, SyntheticHand.openPalm(at: Vec2(0.97, 0.65)))
    }

    func testDoubleClapRestsAndWakes() {
        let sim = Sim()
        var (l, r) = hands()
        sim.hold([l, r], for: 0.3)
        clap(sim, &l, &r)
        XCTAssertTrue(sim.engine.active, "one clap is not enough")
        XCTAssertEqual(sim.lastHUD.cue, .clap)
        clap(sim, &l, &r)
        XCTAssertFalse(sim.engine.active)
        XCTAssertEqual(sim.all.filter { if case .activeChanged = $0 { return true }; return false }, [.activeChanged(false)])
        sim.hold([l, r], for: 1.2)
        clap(sim, &l, &r)
        clap(sim, &l, &r)
        XCTAssertTrue(sim.engine.active)
    }

    func testClapWhereTrackerMergesTheHandsStillCounts() {
        let sim = Sim()
        var (l, r) = hands()
        sim.hold([l, r], for: 0.3)
        clap(sim, &l, &r, merge: true)
        clap(sim, &l, &r, merge: true)
        XCTAssertFalse(sim.engine.active)
    }

    func testSlowlyBringingHandsTogetherIsNotAClap() {
        let sim = Sim()
        var (l, r) = hands()
        sim.hold([l, r], for: 0.3)
        for _ in 0..<3 {
            twoHands(sim, &l, &r, to: 0.6, 0.72, over: 0.8)
            twoHands(sim, &l, &r, to: 0.35, 0.97, over: 0.8)
        }
        XCTAssertTrue(sim.engine.active)
        XCTAssertTrue(sim.effects.isEmpty, "\(sim.effects)")
    }

    func testClapsTooFarApartInTimeDoNothing() {
        let sim = Sim()
        var (l, r) = hands()
        sim.hold([l, r], for: 0.3)
        clap(sim, &l, &r)
        sim.hold([l, r], for: 1.5)
        clap(sim, &l, &r)
        XCTAssertTrue(sim.engine.active)
    }

    func testRestingIgnoresEverythingButTheClap() {
        let sim = Sim()
        _ = sim.engine.setActive(false, time: sim.time)
        var v = SyntheticHand.vee(at: Vec2(0.65, 0.65))
        sim.hold(v, for: 0.3)
        sim.move(&v, by: Vec2(0, -0.15), over: 0.15)
        var p = SyntheticHand.point(at: Vec2(0.65, 0.6))
        sim.hold(p, for: 1.0)
        sim.move(&p, by: Vec2(0.3, 0), over: 0.15)
        XCTAssertTrue(sim.effects.isEmpty)
        XCTAssertEqual(sim.mode, .command)
        XCTAssertFalse(sim.lastHUD.active)
    }

    func testRestingFromPointerModeExitsIt() {
        let sim = Sim()
        _ = sim.enterPointer()
        _ = sim.engine.setActive(false, time: sim.time)
        XCTAssertEqual(sim.mode, .command)
    }
}

final class CurtainsTests: XCTestCase {
    func testPartingTheCurtainsShowsDesktop() {
        let sim = Sim()
        var l = SyntheticHand.openPalm(at: Vec2(0.55, 0.65))
        var r = SyntheticHand.openPalm(at: Vec2(0.80, 0.65))
        sim.hold([l, r], for: 0.5)
        XCTAssertEqual(sim.lastHUD.cue, .curtains)
        twoHands(sim, &l, &r, to: 0.2, 1.15, over: 0.3)
        sim.hold([l, r], for: 0.3)
        XCTAssertEqual(sim.shortcuts, [.showDesktop])
    }

    func testHandsThatWereNeverTogetherDoNothing() {
        let sim = Sim()
        var l = SyntheticHand.openPalm(at: Vec2(0.35, 0.65))
        var r = SyntheticHand.openPalm(at: Vec2(1.0, 0.65))
        sim.hold([l, r], for: 0.4)
        twoHands(sim, &l, &r, to: 0.15, 1.2, over: 0.3)
        XCTAssertFalse(sim.shortcuts.contains(.showDesktop))
    }
}

final class FrameTests: XCTestCase {
    func testFramingWithBothHandsTakesAScreenshot() {
        let sim = Sim()
        var l = SyntheticHand.frameL(at: Vec2(0.4, 0.7))
        l.flipped = true
        let r = SyntheticHand.frameL(at: Vec2(0.95, 0.7))
        sim.hold([l, r], for: 0.3)
        XCTAssertEqual(sim.lastHUD.cue, .frame)
        sim.hold([l, r], for: 0.4)
        XCTAssertEqual(sim.shortcuts, [.screenshot])
        XCTAssertEqual(sim.mode, .command, "two pointing hands must not enter pointer mode")
        sim.hold([l, r], for: 1.0)
        XCTAssertEqual(sim.shortcuts, [.screenshot], "one shot per frame")
    }

    func testOneLHandIsJustPointing() {
        let sim = Sim()
        sim.hold(SyntheticHand.frameL(at: Vec2(0.65, 0.6)), for: 0.8)
        XCTAssertFalse(sim.shortcuts.contains(.screenshot))
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
        // Vertical fist motion means nothing (sideways is the app switcher).
        sim.move(&f, by: Vec2(0.02, -0.25), over: 0.15)
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

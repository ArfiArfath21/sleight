import XCTest
@testable import MaestroCore

final class EngagementTests: XCTestCase {
    func testSteadyOpenPalmEngagesAfterArmTime() {
        let sim = Sim()
        let h = SyntheticHand.openPalm(at: Vec2(0.65, 0.6))
        sim.hold(h, for: 0.2)
        XCTAssertFalse(sim.engine.isEngaged)
        XCTAssertEqual(sim.lastHUD.mode, .arming)
        XCTAssertGreaterThan(sim.lastHUD.armProgress, 0.3)
        sim.hold(h, for: 0.2)
        XCTAssertTrue(sim.engine.isEngaged)
        XCTAssertEqual(sim.count { $0 == .engaged }, 1)
    }

    func testHandPassingThroughNeverEngages() {
        let sim = Sim()
        var h = SyntheticHand.openPalm(at: Vec2(0.1, 0.6))
        sim.move(&h, to: Vec2(1.25, 0.6), over: 0.8) // ~9 hs/s
        XCTAssertFalse(sim.engine.isEngaged)
        XCTAssertEqual(sim.count { $0 == .engaged }, 0)
    }

    func testRelaxedOrFistHandsDoNotEngage() {
        let sim = Sim()
        sim.hold(.fist(at: Vec2(0.65, 0.6)), for: 1.0)
        var curled = SyntheticHand.openPalm(at: Vec2(0.65, 0.6))
        curled.fingers = [1, 1, 0.2, 0.2]
        sim.hold(curled, for: 1.0)
        XCTAssertFalse(sim.engine.isEngaged)
    }

    func testTinyBackgroundHandIgnored() {
        let sim = Sim()
        sim.hold(.openPalm(at: Vec2(0.65, 0.6), scale: 0.03), for: 1.0)
        XCTAssertFalse(sim.engine.isEngaged)
        XCTAssertEqual(sim.lastHUD.hint, .tooFar)
    }

    func testRealInputDisengagesAndBlocksForCooldown() {
        let sim = Sim()
        let h = sim.engage()
        sim.lastRealInput = sim.time
        sim.step(h)
        XCTAssertEqual(sim.disengages, [.userInput])
        sim.hold(h, for: 0.6)
        XCTAssertFalse(sim.engine.isEngaged, "still inside the real-input cooldown")
        sim.hold(h, for: 1.0)
        XCTAssertTrue(sim.engine.isEngaged, "re-arms once the user stops typing")
    }

    func testFlipToBackOfHandDisengagesAndDoesNotReArm() {
        let sim = Sim()
        var h = sim.engage()
        h.flipped = true
        sim.hold(h, for: 0.6)
        XCTAssertEqual(sim.disengages, [.flipped])
        sim.hold(h, for: 1.5)
        XCTAssertFalse(sim.engine.isEngaged, "back of hand must not re-engage")
        h.flipped = false
        sim.hold(h, for: 0.5)
        XCTAssertTrue(sim.engine.isEngaged)
    }

    func testDroppingHandToRestDisengages() {
        let sim = Sim()
        var h = sim.engage()
        sim.move(&h, to: Vec2(0.65, 1.2), over: 0.25)
        sim.hold(h, for: 0.4)
        XCTAssertEqual(sim.disengages.first, .rested)
        XCTAssertFalse(sim.engine.isEngaged)
    }

    func testDroppingHandOutOfViewRewindsCursor() {
        let sim = Sim()
        var h = sim.engage()
        sim.hold(h, for: 0.3)
        let before = sim.systemCursor
        // Fast exit downward, then the hand is gone.
        sim.move(&h, to: Vec2(0.65, 0.9), over: 0.15)
        sim.empty(for: 1.5)
        XCTAssertEqual(sim.disengages, [.lost])
        XCTAssertLessThan(distance(sim.systemCursor, before), 8, "exit motion should be undone")
    }
}

final class PointerTests: XCTestCase {
    func testCursorFollowsHandInMirroredDirection() {
        let sim = Sim()
        var h = sim.engage()
        let start = sim.systemCursor
        sim.move(&h, to: h.wrist + Vec2(0.1, 0), over: 0.5)
        XCTAssertGreaterThan(sim.systemCursor.x - start.x, 50)
        XCTAssertLessThan(abs(sim.systemCursor.y - start.y), 10)
        sim.move(&h, to: h.wrist + Vec2(0, -0.08), over: 0.5)
        XCTAssertLessThan(sim.systemCursor.y, start.y - 30, "hand up = cursor up")
    }

    func testSlowMotionIsPreciseFastMotionCoversGround() {
        func pointsPerHandScale(speedHS: Double) -> Double {
            let sim = Sim()
            var h = sim.engage()
            sim.hold(h, for: 0.3)
            let start = sim.systemCursor
            let dist = 0.5 * h.scale // half a hand scale
            sim.move(&h, to: h.wrist + Vec2(dist, 0), over: 0.5 / speedHS)
            sim.hold(h, for: 0.3)
            return (sim.systemCursor.x - start.x) / 0.5
        }
        let slow = pointsPerHandScale(speedHS: 0.2)
        let medium = pointsPerHandScale(speedHS: 1.5)
        let fast = pointsPerHandScale(speedHS: 5)
        XCTAssertLessThan(slow, 140, "precision mode should engage when slow")
        XCTAssertGreaterThan(medium, slow * 2)
        XCTAssertGreaterThan(fast, medium * 1.8)
    }

    func testNoisyStillHandKeepsCursorSteady() {
        let sim = Sim()
        sim.noise = 0.0025 // ~1.6 px of jitter at 640x480
        let h = sim.engage()
        sim.hold(h, for: 0.3)
        let start = sim.systemCursor
        var worst = 0.0
        for _ in 0..<60 {
            sim.step(h)
            worst = max(worst, distance(sim.systemCursor, start))
        }
        XCTAssertLessThan(worst, 6, "jitter leaking into the cursor")
    }

    func testCursorStaysOnScreen() {
        let sim = Sim()
        var h = sim.engage()
        sim.move(&h, to: Vec2(0.05, 0.25), over: 0.3)
        sim.hold(h, for: 1.0)
        XCTAssertGreaterThanOrEqual(sim.systemCursor.x, 0)
        XCTAssertGreaterThanOrEqual(sim.systemCursor.y, 0)
        XCTAssertLessThan(sim.systemCursor.x, 1512)
    }

    func testEdgeGlideKeepsMovingWhenHandHitsFrameEdge() {
        let sim = Sim()
        sim.systemCursor = Vec2(100, 450)
        var h = sim.engage(at: Vec2(1.15, 0.6))
        // Push to the right edge of the camera frame (x spans 0…4/3).
        let anchorX = h.anchorOffset.x
        sim.move(&h, to: Vec2(4.0 / 3.0 - 0.02 - anchorX, 0.6), over: 0.6)
        let atEdge = sim.systemCursor.x
        sim.hold(h, for: 0.5)
        XCTAssertGreaterThan(sim.systemCursor.x, atEdge + 100, "cursor should keep gliding")
    }

    func testAbsoluteModeMapsFrameToScreen() {
        var cfg = MaestroConfig()
        cfg.mappingMode = .absolute
        let sim = Sim(config: cfg)
        var h = sim.engage(at: Vec2(0.65, 0.6))
        let off = h.anchorOffset
        // Anchor at the centre of the frame -> centre of the screen.
        sim.move(&h, to: Vec2(4.0 / 6.0, 0.5) - off, over: 0.3)
        sim.hold(h, for: 0.8)
        XCTAssertEqual(sim.systemCursor.x, 756, accuracy: 30)
        XCTAssertEqual(sim.systemCursor.y, 491, accuracy: 30)
    }
}

final class ClickTests: XCTestCase {
    /// Closes a pinch over `seconds`, flexing the index a bit and drifting the
    /// wrist the way a real hand does.
    func pinch(_ sim: Sim, _ h: inout SyntheticHand, closeOver seconds: Double = 0.12,
               drift: Vec2 = Vec2(0, 0.012)) {
        sim.move(&h, to: h.wrist + drift, over: seconds) { hand, f in
            hand.pinch = f
            hand.fingers[0] = lerp(1, 0.6, f)
        }
    }

    func release(_ sim: Sim, _ h: inout SyntheticHand, over seconds: Double = 0.1) {
        sim.move(&h, to: h.wrist, over: seconds) { hand, f in
            hand.pinch = 1 - f
            hand.fingers[0] = lerp(0.6, 1, f)
        }
    }

    func testPinchClicksWhereCursorWasBeforeFingersMoved() {
        let sim = Sim()
        var h = sim.engage()
        sim.move(&h, to: h.wrist + Vec2(0.05, 0.02), over: 0.4)
        sim.hold(h, for: 0.3)
        let aim = sim.systemCursor
        sim.clear()
        pinch(sim, &h)
        sim.hold(h, for: 0.1)
        release(sim, &h)
        XCTAssertEqual(sim.downs.count, 1)
        XCTAssertEqual(sim.ups.count, 1)
        XCTAssertLessThan(distance(sim.downs[0].1, aim), 1.5, "click must land on the aimed point")
        XCTAssertLessThan(distance(sim.ups[0].1, aim), 1.5, "no drag on a plain click")
        XCTAssertEqual(sim.downs[0].0, .left)
    }

    func testPinchHysteresisPreventsChatter() {
        let sim = Sim()
        var h = sim.engage()
        sim.hold(h, for: 0.2)
        sim.clear()
        h.pinch = 0.85
        h.fingers[0] = 0.65
        sim.hold(h, for: 0.1)
        // Wobble between "clearly closed" and "almost open" (inside the hysteresis band).
        for i in 0..<30 {
            h.pinch = i % 2 == 0 ? 0.68 : 0.85
            sim.step(h)
        }
        h.pinch = 0
        h.fingers[0] = 1
        sim.hold(h, for: 0.2)
        XCTAssertEqual(sim.downs.count, 1)
        XCTAssertEqual(sim.ups.count, 1)
    }

    func testDoubleClick() {
        let sim = Sim()
        var h = sim.engage()
        sim.hold(h, for: 0.2)
        sim.clear()
        pinch(sim, &h, closeOver: 0.07, drift: .zero)
        release(sim, &h, over: 0.07)
        sim.hold(h, for: 0.07)
        pinch(sim, &h, closeOver: 0.07, drift: .zero)
        release(sim, &h, over: 0.07)
        XCTAssertEqual(sim.downs.map(\.2), [1, 2])
        XCTAssertEqual(sim.ups.map(\.2), [1, 2])
    }

    func testSeparatePinchesFarApartAreSingleClicks() {
        let sim = Sim()
        var h = sim.engage()
        sim.clear()
        pinch(sim, &h, drift: .zero)
        release(sim, &h)
        sim.hold(h, for: 0.6)
        pinch(sim, &h, drift: .zero)
        release(sim, &h)
        XCTAssertEqual(sim.downs.map(\.2), [1, 1])
    }

    func testPinchHoldAndMoveDrags() {
        let sim = Sim()
        var h = sim.engage()
        sim.hold(h, for: 0.2)
        sim.clear()
        pinch(sim, &h, drift: .zero)
        let downAt = sim.systemCursor
        var sawDragging = false
        sim.move(&h, to: h.wrist + Vec2(0.08, 0), over: 0.4) { _, _ in }
        sawDragging = sim.lastHUD.mode == .dragging
        release(sim, &h)
        XCTAssertTrue(sawDragging)
        XCTAssertEqual(sim.downs.count, 1)
        XCTAssertEqual(sim.ups.count, 1)
        XCTAssertGreaterThan(sim.ups[0].1.x - downAt.x, 40, "drag should carry the cursor")
        let downIdx = sim.actions.firstIndex { if case .mouseDown = $0.action { return true }; return false }!
        let upIdx = sim.actions.firstIndex { if case .mouseUp = $0.action { return true }; return false }!
        let movesWhileHeld = sim.actions[downIdx..<upIdx].filter { if case .move = $0.action { return true }; return false }
        XCTAssertGreaterThan(movesWhileHeld.count, 5)
    }

    func testRightClickWithMiddleFingerPinch() {
        let sim = Sim()
        var h = sim.engage()
        sim.clear()
        sim.move(&h, to: h.wrist, over: 0.1) { hand, f in hand.middlePinch = f }
        sim.hold(h, for: 0.1)
        sim.move(&h, to: h.wrist, over: 0.1) { hand, f in hand.middlePinch = 1 - f }
        sim.hold(h, for: 0.1)
        XCTAssertEqual(sim.downs.map(\.0), [.right])
        XCTAssertEqual(sim.ups.map(\.0), [.right])
    }

    func testMakingAFistNeverClicks() {
        let sim = Sim()
        var h = sim.engage()
        sim.clear()
        sim.move(&h, to: h.wrist, over: 0.15) { hand, f in hand.fingers = [1 - f, 1 - f, 1 - f, 1 - f] }
        sim.hold(h, for: 0.3)
        XCTAssertEqual(sim.downs.count, 0)
    }
}

final class ScrollTests: XCTestCase {
    func testFistScrollsNaturallyAndCoasts() {
        let sim = Sim()
        var h = sim.engage()
        sim.clear()
        sim.move(&h, to: h.wrist, over: 0.12) { hand, f in hand.fingers = [1 - f, 1 - f, 1 - f, 1 - f] }
        sim.hold(h, for: 0.1)
        let cursorBefore = sim.systemCursor
        sim.move(&h, to: h.wrist + Vec2(0, -0.1), over: 0.25)
        // Let go while still moving.
        sim.move(&h, to: h.wrist + Vec2(0, -0.01), over: 0.07) { hand, f in hand.fingers = [f, f, f, f] }
        sim.hold(h, for: 0.1)

        let phases = sim.scrolls.map(\.1)
        XCTAssertEqual(phases.first, .began)
        XCTAssertEqual(phases.last, .ended)
        let total = sim.scrolls.reduce(Vec2.zero) { $0 + $1.0 }
        XCTAssertLessThan(total.y, -300, "fist moving up should scroll content up (negative wheel)")
        XCTAssertEqual(sim.downs.count, 0)
        XCTAssertLessThan(distance(sim.systemCursor, cursorBefore), 3, "cursor stays put while scrolling")
        let momentum = sim.actions.contains { if case .scrollMomentum(let v) = $0.action { return v.y < 0 }; return false }
        XCTAssertTrue(momentum, "released mid-motion should coast")
    }

    func testStillFistReleaseHasNoMomentum() {
        let sim = Sim()
        var h = sim.engage()
        sim.clear()
        sim.move(&h, to: h.wrist, over: 0.12) { hand, f in hand.fingers = [1 - f, 1 - f, 1 - f, 1 - f] }
        sim.hold(h, for: 0.4)
        sim.move(&h, to: h.wrist, over: 0.1) { hand, f in hand.fingers = [f, f, f, f] }
        sim.hold(h, for: 0.1)
        XCTAssertFalse(sim.actions.contains { if case .scrollMomentum = $0.action { return true }; return false })
    }
}

final class SwipeTests: XCTestCase {
    func testFlicksSwipeAndRewindCursor() {
        for (offset, expected) in [(Vec2(-0.3, 0), SwipeDirection.left),
                                   (Vec2(0.3, 0), .right),
                                   (Vec2(0, -0.3), .up)] {
            let sim = Sim()
            var h = sim.engage(at: Vec2(0.65, 0.7))
            sim.hold(h, for: 0.3)
            let before = sim.systemCursor
            sim.clear()
            sim.move(&h, to: h.wrist + offset, over: 0.13)
            sim.hold(h, for: 0.2)
            XCTAssertEqual(sim.swipes, [expected], "\(expected)")
            XCTAssertLessThan(distance(sim.systemCursor, before), 40, "swipe should not fling the cursor")
        }
    }

    func testOrdinaryPointingNeverSwipes() {
        let sim = Sim()
        var h = sim.engage(at: Vec2(0.4, 0.65))
        sim.move(&h, to: Vec2(0.9, 0.65), over: 0.5)   // ~6 hs/s, a quick but normal move
        sim.move(&h, to: Vec2(0.45, 0.55), over: 0.7)
        sim.move(&h, to: Vec2(0.7, 0.4), over: 0.4)
        XCTAssertEqual(sim.swipes, [])
    }

    func testSwipeFiresOnceAndIgnoresReturnStroke() {
        let sim = Sim()
        var h = sim.engage(at: Vec2(0.8, 0.7))
        sim.move(&h, to: h.wrist + Vec2(-0.3, 0), over: 0.13)
        sim.move(&h, to: h.wrist + Vec2(0.3, 0), over: 0.13)
        sim.hold(h, for: 0.3)
        XCTAssertEqual(sim.swipes, [.left])
    }
}

final class TrackingLossTests: XCTestCase {
    func testShortDropoutIsBridged() {
        let sim = Sim()
        let h = sim.engage()
        sim.hold(h, for: 0.3)
        let before = sim.systemCursor
        sim.empty(for: 0.15)
        XCTAssertEqual(sim.lastHUD.mode, .lost)
        sim.hold(h, for: 0.3)
        XCTAssertTrue(sim.engine.isEngaged)
        XCTAssertTrue(sim.disengages.isEmpty)
        XCTAssertLessThan(distance(sim.systemCursor, before), 2)
    }

    func testLongDropoutReleasesDragAndDisengages() {
        let sim = Sim()
        var h = sim.engage()
        sim.move(&h, to: h.wrist, over: 0.12) { hand, f in hand.pinch = f; hand.fingers[0] = lerp(1, 0.6, f) }
        XCTAssertEqual(sim.downs.count, 1)
        sim.empty(for: 0.4)
        XCTAssertEqual(sim.ups.count, 1, "never leave a mouse button stuck down")
        sim.empty(for: 1.0)
        XCTAssertEqual(sim.disengages, [.lost])
    }

    func testGlitchJumpToAnotherHandIsIgnored() {
        let sim = Sim()
        let h = sim.engage(at: Vec2(0.4, 0.6))
        sim.hold(h, for: 0.2)
        let before = sim.systemCursor
        let stranger = SyntheticHand.openPalm(at: Vec2(1.1, 0.5))
        sim.step(stranger)
        sim.step(stranger)
        XCTAssertLessThan(distance(sim.systemCursor, before), 1)
        sim.hold(h, for: 0.2)
        XCTAssertTrue(sim.engine.isEngaged)
        XCTAssertLessThan(distance(sim.systemCursor, before), 2)
    }

    func testFollowsTheEngagedHandWhenASecondHandAppears() {
        let sim = Sim()
        var h = sim.engage(at: Vec2(0.4, 0.6))
        let other = SyntheticHand.openPalm(at: Vec2(1.0, 0.6))
        let start = sim.systemCursor
        for i in 1...15 {
            h.wrist = Vec2(0.4 + 0.005 * Double(i), 0.6)
            sim.step([other, h])
        }
        XCTAssertGreaterThan(sim.systemCursor.x, start.x + 10)
        XCTAssertTrue(sim.disengages.isEmpty)
    }

    func testLowConfidenceFramesCountAsMissing() {
        let sim = Sim()
        var h = sim.engage()
        h.confidence = 0.1
        sim.hold(h, for: 1.6)
        XCTAssertEqual(sim.disengages, [.lost])
    }
}

final class KeyboardGestureTests: XCTestCase {
    func testHoldingPeaceSignTogglesKeyboardOnce() {
        let sim = Sim()
        let h = sim.engage()
        sim.clear()
        let peace = SyntheticHand.peace(at: h.wrist)
        sim.hold(peace, for: 0.3)
        XCTAssertGreaterThan(sim.lastHUD.keyboardProgress, 0.3)
        sim.hold(peace, for: 1.0)
        XCTAssertEqual(sim.count { $0 == .toggleKeyboard }, 1)
    }
}

final class ForceDisengageTests: XCTestCase {
    func testForceDisengageReleasesButton() {
        let sim = Sim()
        var h = sim.engage()
        sim.move(&h, to: h.wrist, over: 0.12) { hand, f in hand.pinch = f; hand.fingers[0] = lerp(1, 0.6, f) }
        let actions = sim.engine.forceDisengage()
        XCTAssertTrue(actions.contains { if case .mouseUp = $0 { return true }; return false })
        XCTAssertTrue(actions.contains(.disengaged(.manual)))
    }
}

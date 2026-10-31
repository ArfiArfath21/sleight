import XCTest
@testable import MaestroCore

final class OneEuroFilterTests: XCTestCase {
    func testSmoothsJitterAtRest() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.01)
        var rng = SplitMix64(seed: 1)
        var raw: [Double] = [], out: [Double] = []
        for i in 0..<300 {
            let v = 500 + rng.gaussian() * 3
            raw.append(v)
            out.append(f.filter(v, time: Double(i) / 30))
        }
        func sd(_ a: ArraySlice<Double>) -> Double {
            let m = a.reduce(0, +) / Double(a.count)
            return (a.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(a.count)).squareRoot()
        }
        XCTAssertLessThan(sd(out[50...]), sd(raw[50...]) * 0.4)
    }

    func testFollowsFastMotionWithLittleLag() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.01)
        var last = 0.0
        for i in 0..<60 {
            let t = Double(i) / 30
            last = f.filter(t * 1500, time: t) // 1500 units/s ramp
        }
        let truth = Double(59) / 30 * 1500
        XCTAssertLessThan(truth - last, 120, "lag should be under ~80 ms of motion")
    }

    func testResetStartsFresh() {
        var f = OneEuroFilter2D(minCutoff: 1, beta: 0)
        _ = f.filter(Vec2(0, 0), time: 0)
        _ = f.filter(Vec2(0, 0), time: 0.03)
        f.reset()
        XCTAssertEqual(f.filter(Vec2(100, 100), time: 0.06), Vec2(100, 100))
    }
}

final class HandPoseTests: XCTestCase {
    let cfg = MaestroConfig()

    func testOpenPalm() throws {
        let p = try XCTUnwrap(HandPose.make(from: SyntheticHand.openPalm(at: Vec2(0.6, 0.6)).frame(), config: cfg))
        XCTAssertTrue(p.isOpenPalm)
        XCTAssertFalse(p.isFist(config: cfg))
        XCTAssertGreaterThan(p.pinchIndex, cfg.pinchOpen)
    }

    func testFist() throws {
        let p = try XCTUnwrap(HandPose.make(from: SyntheticHand.fist(at: Vec2(0.6, 0.6)).frame(), config: cfg))
        XCTAssertTrue(p.isFist(config: cfg))
        XCTAssertEqual(p.extendedCount, 0)
    }

    func testPeace() throws {
        let p = try XCTUnwrap(HandPose.make(from: SyntheticHand.peace(at: Vec2(0.6, 0.6)).frame(), config: cfg))
        XCTAssertTrue(p.isPeace)
    }

    func testPinchDistanceClosesBelowThreshold() throws {
        var h = SyntheticHand.openPalm(at: Vec2(0.6, 0.6))
        h.pinch = 1
        h.fingers[0] = 0.6
        let p = try XCTUnwrap(HandPose.make(from: h.frame(), config: cfg))
        XCTAssertLessThan(p.pinchIndex, cfg.pinchClose)
        XCTAssertGreaterThanOrEqual(p.indexRatio(), cfg.pinchMinIndexExtension)
    }

    func testScaleIsDistanceInvariant() throws {
        let near = try XCTUnwrap(HandPose.make(from: SyntheticHand.openPalm(at: Vec2(0.6, 0.6), scale: 0.25).frame(), config: cfg))
        let far = try XCTUnwrap(HandPose.make(from: SyntheticHand.openPalm(at: Vec2(0.6, 0.6), scale: 0.1).frame(), config: cfg))
        XCTAssertEqual(near.pinchIndex, far.pinchIndex, accuracy: 1e-9)
        XCTAssertEqual(near.scale / far.scale, 2.5, accuracy: 1e-6)
    }

    func testOrientationFlipsWithBackOfHandButNotWithRotation() throws {
        var h = SyntheticHand.openPalm(at: Vec2(0.6, 0.6))
        let palm = try XCTUnwrap(HandPose.make(from: h.frame(), config: cfg)).orientation
        h.rotation = 0.9
        let rotated = try XCTUnwrap(HandPose.make(from: h.frame(), config: cfg)).orientation
        h.flipped = true
        let back = try XCTUnwrap(HandPose.make(from: h.frame(), config: cfg)).orientation
        XCTAssertEqual(palm.sign, rotated.sign)
        XCTAssertNotEqual(palm.sign, back.sign)
        XCTAssertGreaterThan(abs(palm), 0.2)
    }

    func testLowConfidenceGhostHandRejected() {
        var h = SyntheticHand.openPalm(at: Vec2(0.6, 0.6))
        h.confidence = 0.32
        XCTAssertNil(HandPose.make(from: h.frame(), config: cfg))
        h.confidence = 0.7
        XCTAssertNotNil(HandPose.make(from: h.frame(), config: cfg))
    }

    func testMissingKeyJointRejectsFrame() {
        var f = SyntheticHand.openPalm(at: Vec2(0.6, 0.6)).frame()
        f[.thumbTip] = nil
        XCTAssertNil(HandPose.make(from: f, config: cfg))
    }
}

final class ConfigTests: XCTestCase {
    func testDecodeKeepsDefaultsForMissingKeys() throws {
        let cfg = try MaestroConfig.decode(from: Data(#"{"slowGain": 123, "unknownKey": 5}"#.utf8))
        XCTAssertEqual(cfg.slowGain, 123)
        XCTAssertEqual(cfg.fastGain, MaestroConfig.default.fastGain)
    }

    func testRoundTrip() throws {
        var cfg = MaestroConfig()
        cfg.mappingMode = .absolute
        cfg.preferredHand = .left
        let back = try MaestroConfig.decode(from: JSONEncoder().encode(cfg))
        XCTAssertEqual(back, cfg)
    }
}

final class ScreenLayoutTests: XCTestCase {
    func testClampToNearestDisplayInLShapedLayout() {
        let layout = ScreenLayout(screens: [ScreenRect(x: 0, y: 0, width: 1512, height: 982),
                                            ScreenRect(x: 1512, y: -500, width: 2560, height: 1440)])
        // In the gap below the external display, to the right of the laptop.
        let p = layout.clamp(Vec2(2000, 1200))
        XCTAssertTrue(layout.screens.contains { $0.contains(p) })
        XCTAssertEqual(layout.clamp(Vec2(100, 100)), Vec2(100, 100))
    }
}

final class HistoryTests: XCTestCase {
    func testValueAtOrBefore() {
        var h = TimedHistory<Int>(span: 1)
        for i in 0..<10 { h.append(i, at: Double(i) * 0.1) }
        XCTAssertEqual(h.value(atOrBefore: 0.45), 4)
        XCTAssertEqual(h.value(atOrBefore: -5), 0)
        h.append(99, at: 5)
        XCTAssertEqual(h.samples.count, 1, "old samples expire")
    }
}

final class RecordingTests: XCTestCase {
    func testJSONLinesRoundTrip() throws {
        let frames = (0..<3).map { RecordedFrame(time: Double($0), aspect: 4.0 / 3.0, hands: [SyntheticHand().frame()]) }
        let enc = JSONEncoder()
        var data = Data()
        for f in frames { data.append(try enc.encode(f)); data.append(UInt8(ascii: "\n")) }
        let back = try RecordedFrame.load(jsonLines: data)
        XCTAssertEqual(back.count, 3)
        XCTAssertEqual(back[1].hands, frames[1].hands)
    }
}

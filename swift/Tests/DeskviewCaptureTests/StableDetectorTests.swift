import XCTest
@testable import DeskviewCapture

final class StableDetectorTests: XCTestCase {
    func testThresholdMappingByName() {
        XCTAssertEqual(StableDetector.threshold(for: "low"), 0.05, accuracy: 1e-9)
        XCTAssertEqual(StableDetector.threshold(for: "medium"), 0.02, accuracy: 1e-9)
        XCTAssertEqual(StableDetector.threshold(for: "high"), 0.005, accuracy: 1e-9)
    }

    func testThresholdDefaultsToMediumOnUnknown() {
        XCTAssertEqual(StableDetector.threshold(for: "asdf"), 0.02, accuracy: 1e-9)
    }

    func testMotionFractionAllSamePixels() {
        let a = [UInt8](repeating: 100, count: 64 * 48)
        let b = [UInt8](repeating: 100, count: 64 * 48)
        XCTAssertEqual(StableDetector.motionFraction(prev: a, curr: b, deltaThreshold: 15), 0.0)
    }

    func testMotionFractionAllChangedPixels() {
        let a = [UInt8](repeating: 0, count: 64 * 48)
        let b = [UInt8](repeating: 200, count: 64 * 48)
        XCTAssertEqual(StableDetector.motionFraction(prev: a, curr: b, deltaThreshold: 15), 1.0)
    }

    func testMotionFractionIgnoresChangesBelowThreshold() {
        // 14 < 15 threshold, so zero pixels count as motion.
        let a = [UInt8](repeating: 0, count: 64 * 48)
        let b = [UInt8](repeating: 14, count: 64 * 48)
        XCTAssertEqual(StableDetector.motionFraction(prev: a, curr: b, deltaThreshold: 15), 0.0)
    }

    func testMotionFractionHalfChanged() {
        var a = [UInt8](repeating: 0, count: 64 * 48)
        var b = [UInt8](repeating: 0, count: 64 * 48)
        for i in 0..<(64 * 48 / 2) {
            b[i] = 200
        }
        XCTAssertEqual(StableDetector.motionFraction(prev: a, curr: b, deltaThreshold: 15), 0.5, accuracy: 0.001)
    }

    func testStabilityCounterIncrementsBelowThresholdAndResetsAbove() {
        var counter = StableDetector.StabilityCounter()
        XCTAssertEqual(counter.update(motion: 0.01, threshold: 0.02), 1)
        XCTAssertEqual(counter.update(motion: 0.005, threshold: 0.02), 2)
        XCTAssertEqual(counter.update(motion: 0.10, threshold: 0.02), 0)
        XCTAssertEqual(counter.update(motion: 0.0, threshold: 0.02), 1)
    }
}

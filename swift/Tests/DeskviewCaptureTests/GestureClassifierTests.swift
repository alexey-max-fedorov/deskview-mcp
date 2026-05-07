import XCTest
@testable import DeskviewCapture
import CoreGraphics

final class GestureClassifierTests: XCTestCase {
    // Helper: y in Vision = top-of-image origin. "Above" means smaller y.
    private func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    private func thumbsUpLandmarks() -> HandLandmarks {
        // Thumb high, all other tips low.
        return [
            .thumbTip: at(0.5, 0.1), .thumbMCP: at(0.5, 0.4),
            .indexTip: at(0.55, 0.7), .indexPIP: at(0.55, 0.5), .indexMCP: at(0.55, 0.4),
            .middleTip: at(0.5, 0.7), .middlePIP: at(0.5, 0.5), .middleMCP: at(0.5, 0.4),
            .ringTip: at(0.45, 0.7), .ringPIP: at(0.45, 0.5), .ringMCP: at(0.45, 0.4),
            .pinkyTip: at(0.4, 0.7), .pinkyPIP: at(0.4, 0.5), .pinkyMCP: at(0.4, 0.4),
        ]
    }

    func testThumbsUpMatchesItself() {
        XCTAssertTrue(GestureClassifier.matches(.thumbsUp, landmarks: thumbsUpLandmarks()))
    }

    func testThumbsUpRejectsThumbDown() {
        var lm = thumbsUpLandmarks()
        lm[.thumbTip] = at(0.5, 0.6) // thumb tip below MCP
        XCTAssertFalse(GestureClassifier.matches(.thumbsUp, landmarks: lm))
    }

    func testThumbsUpRejectsIndexUp() {
        var lm = thumbsUpLandmarks()
        lm[.indexTip] = at(0.55, 0.3) // index above its PIP
        XCTAssertFalse(GestureClassifier.matches(.thumbsUp, landmarks: lm))
    }

    func testPeace() {
        let lm: HandLandmarks = [
            .indexTip: at(0.5, 0.1), .indexPIP: at(0.5, 0.4),
            .middleTip: at(0.55, 0.1), .middlePIP: at(0.55, 0.4),
            .ringTip: at(0.6, 0.7), .ringPIP: at(0.6, 0.5),
            .pinkyTip: at(0.65, 0.7), .pinkyPIP: at(0.65, 0.5),
        ]
        XCTAssertTrue(GestureClassifier.matches(.peace, landmarks: lm))
    }

    func testOkSignNeedsCloseThumbAndIndex() {
        var lm: HandLandmarks = [
            .thumbTip: at(0.50, 0.50),
            .indexTip: at(0.51, 0.51),
            .middleTip: at(0.55, 0.10), .middlePIP: at(0.55, 0.40),
            .ringTip: at(0.60, 0.10), .ringPIP: at(0.60, 0.40),
            .pinkyTip: at(0.65, 0.10), .pinkyPIP: at(0.65, 0.40),
        ]
        XCTAssertTrue(GestureClassifier.matches(.okSign, landmarks: lm))

        lm[.indexTip] = at(0.80, 0.80)
        XCTAssertFalse(GestureClassifier.matches(.okSign, landmarks: lm))
    }

    func testFist() {
        let lm: HandLandmarks = [
            .thumbTip: at(0.50, 0.60), .thumbMCP: at(0.50, 0.40),
            .indexTip: at(0.55, 0.60), .indexMCP: at(0.55, 0.40),
            .middleTip: at(0.50, 0.60), .middleMCP: at(0.50, 0.40),
            .ringTip: at(0.45, 0.60), .ringMCP: at(0.45, 0.40),
            .pinkyTip: at(0.40, 0.60), .pinkyMCP: at(0.40, 0.40),
        ]
        XCTAssertTrue(GestureClassifier.matches(.fist, landmarks: lm))
    }

    func testOpenPalm() {
        let lm: HandLandmarks = [
            .thumbTip: at(0.30, 0.10),
            .indexTip: at(0.50, 0.10), .indexPIP: at(0.50, 0.40),
            .middleTip: at(0.55, 0.10), .middlePIP: at(0.55, 0.40),
            .ringTip: at(0.60, 0.10), .ringPIP: at(0.60, 0.40),
            .pinkyTip: at(0.65, 0.10), .pinkyPIP: at(0.65, 0.40),
        ]
        XCTAssertTrue(GestureClassifier.matches(.openPalm, landmarks: lm))
    }

    func testMissingLandmarksReturnsFalse() {
        let lm: HandLandmarks = [.thumbTip: at(0, 0)]
        for kind in [GestureKind.thumbsUp, .peace, .okSign, .fist, .openPalm] {
            XCTAssertFalse(GestureClassifier.matches(kind, landmarks: lm), "\(kind) should fail on partial data")
        }
    }

    func testHoldCounterIncrementsAndResets() {
        var c = GestureClassifier.HoldCounter()
        XCTAssertEqual(c.update(matched: true), 1)
        XCTAssertEqual(c.update(matched: true), 2)
        XCTAssertEqual(c.update(matched: false), 0)
        XCTAssertEqual(c.update(matched: true), 1)
    }
}

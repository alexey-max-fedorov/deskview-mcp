import Foundation
import CoreGraphics

enum HandJoint: String {
    case thumbTip, thumbMCP
    case indexTip, indexPIP, indexMCP
    case middleTip, middlePIP, middleMCP
    case ringTip, ringPIP, ringMCP
    case pinkyTip, pinkyPIP, pinkyMCP
}

typealias HandLandmarks = [HandJoint: CGPoint]

enum GestureKind: String {
    case thumbsUp = "thumbs_up"
    case peace
    case okSign = "ok_sign"
    case fist
    case openPalm = "open_palm"
}

enum GestureClassifier {
    // Vision uses top-of-image origin; "above" means smaller y (rising on screen).
    // We treat smaller y as "higher".
    static func isAbove(_ a: CGPoint, _ b: CGPoint) -> Bool { a.y < b.y }
    static func isBelow(_ a: CGPoint, _ b: CGPoint) -> Bool { a.y > b.y }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return sqrt(Double(dx * dx + dy * dy))
    }

    static func matches(_ kind: GestureKind, landmarks lm: HandLandmarks) -> Bool {
        switch kind {
        case .thumbsUp:
            guard let tT = lm[.thumbTip], let tM = lm[.thumbMCP],
                  let iT = lm[.indexTip], let iP = lm[.indexPIP],
                  let mT = lm[.middleTip], let mP = lm[.middlePIP],
                  let rT = lm[.ringTip], let rP = lm[.ringPIP],
                  let pT = lm[.pinkyTip], let pP = lm[.pinkyPIP] else { return false }
            return isAbove(tT, tM)
                && isBelow(iT, iP) && isBelow(mT, mP) && isBelow(rT, rP) && isBelow(pT, pP)
        case .peace:
            guard let iT = lm[.indexTip], let iP = lm[.indexPIP],
                  let mT = lm[.middleTip], let mP = lm[.middlePIP],
                  let rT = lm[.ringTip], let rP = lm[.ringPIP],
                  let pT = lm[.pinkyTip], let pP = lm[.pinkyPIP] else { return false }
            return isAbove(iT, iP) && isAbove(mT, mP) && isBelow(rT, rP) && isBelow(pT, pP)
        case .okSign:
            guard let tT = lm[.thumbTip], let iT = lm[.indexTip],
                  let mT = lm[.middleTip], let mP = lm[.middlePIP],
                  let rT = lm[.ringTip], let rP = lm[.ringPIP],
                  let pT = lm[.pinkyTip], let pP = lm[.pinkyPIP] else { return false }
            // 30 normalized units in the PRD: Vision returns 0..1, so 30 of 1000 is 0.03.
            return distance(tT, iT) < 0.03
                && isAbove(mT, mP) && isAbove(rT, rP) && isAbove(pT, pP)
        case .fist:
            guard let tT = lm[.thumbTip], let tM = lm[.thumbMCP],
                  let iT = lm[.indexTip], let iM = lm[.indexMCP],
                  let mT = lm[.middleTip], let mM = lm[.middleMCP],
                  let rT = lm[.ringTip], let rM = lm[.ringMCP],
                  let pT = lm[.pinkyTip], let pM = lm[.pinkyMCP] else { return false }
            return isBelow(tT, tM) && isBelow(iT, iM) && isBelow(mT, mM)
                && isBelow(rT, rM) && isBelow(pT, pM)
        case .openPalm:
            guard let tT = lm[.thumbTip], let iP = lm[.indexPIP],
                  let iT = lm[.indexTip],
                  let mT = lm[.middleTip], let mP = lm[.middlePIP],
                  let rT = lm[.ringTip], let rP = lm[.ringPIP],
                  let pT = lm[.pinkyTip], let pP = lm[.pinkyPIP] else { return false }
            // Thumb has no PIP; require it above index PIP (a reasonable proxy for spread palm).
            return isAbove(tT, iP) && isAbove(iT, iP) && isAbove(mT, mP)
                && isAbove(rT, rP) && isAbove(pT, pP)
        }
    }

    struct HoldCounter {
        private(set) var consecutive = 0
        @discardableResult
        mutating func update(matched: Bool) -> Int {
            consecutive = matched ? consecutive + 1 : 0
            return consecutive
        }
    }
}

import Foundation

enum StableDetector {
    static let downsampledWidth = 64
    static let downsampledHeight = 48
    static let totalPixels = downsampledWidth * downsampledHeight

    static func threshold(for sensitivity: String) -> Double {
        switch sensitivity {
        case "low": return 0.05
        case "high": return 0.005
        default: return 0.02
        }
    }

    static func motionFraction(prev: [UInt8], curr: [UInt8], deltaThreshold: Int) -> Double {
        precondition(prev.count == curr.count)
        var count = 0
        let n = prev.count
        for i in 0..<n {
            let d = Int(prev[i]) - Int(curr[i])
            if abs(d) > deltaThreshold { count += 1 }
        }
        return Double(count) / Double(n)
    }

    struct StabilityCounter {
        private(set) var consecutive = 0
        @discardableResult
        mutating func update(motion: Double, threshold: Double) -> Int {
            if motion <= threshold {
                consecutive += 1
            } else {
                consecutive = 0
            }
            return consecutive
        }
    }
}

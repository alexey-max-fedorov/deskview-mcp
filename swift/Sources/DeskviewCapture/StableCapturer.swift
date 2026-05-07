import Foundation
import AVFoundation
import CoreImage

final class StableCapturer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session: DeskViewSession
    private let stabilityDurationMs: Int
    private let timeoutMs: Int
    private let threshold: Double
    private let frameIntervalMs: Int = 100  // 10fps

    private let semaphore = DispatchSemaphore(value: 0)
    private var counter = StableDetector.StabilityCounter()
    private var prevDownsampled: [UInt8]?
    private var lastFullFrame: (base64: String, w: Int, h: Int)?
    private var pendingResult: (base64: String, w: Int, h: Int, status: String)?
    private var captureError: DeskviewError?
    private let started = Date()
    private let ciContext = CIContext(options: nil)

    init(session: DeskViewSession, stabilityDurationMs: Int, timeoutMs: Int, sensitivity: String) {
        self.session = session
        self.stabilityDurationMs = stabilityDurationMs
        self.timeoutMs = timeoutMs
        self.threshold = StableDetector.threshold(for: sensitivity)
    }

    func run() throws -> (base64: String, w: Int, h: Int, status: String, waitMs: Int, deviceName: String) {
        let output = try session.configureForStillCapture()
        let queue = DispatchQueue(label: "deskview.stable")
        output.setSampleBufferDelegate(self, queue: queue)
        session.start()

        let deadline = DispatchTime.now() + .milliseconds(timeoutMs + 500)
        _ = semaphore.wait(timeout: deadline)
        session.stop()

        let waitMs = Int(Date().timeIntervalSince(started) * 1000)
        if let err = captureError { throw err }

        if let p = pendingResult {
            return (p.base64, p.w, p.h, p.status, waitMs, session.deviceName)
        }
        // Hard timeout: surface last frame if any, else error.
        if let f = lastFullFrame {
            return (f.base64, f.w, f.h, "timeout", waitMs, session.deviceName)
        }
        throw DeskviewError.timeout
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard pendingResult == nil else { return }

        // Always keep the most recent full-resolution frame for fallback.
        if let png = try? ImageEncoder.pngBase64(from: sampleBuffer) {
            lastFullFrame = (png.base64, png.width, png.height)
        }

        // Compute downsampled grayscale buffer for diff.
        guard let curr = downsampledLuma(from: sampleBuffer) else { return }

        if let prev = prevDownsampled {
            let motion = StableDetector.motionFraction(prev: prev, curr: curr, deltaThreshold: 15)
            let consec = counter.update(motion: motion, threshold: threshold)
            let stableMs = consec * frameIntervalMs
            logStderr("stable: motion=\(String(format: "%.4f", motion)) stableMs=\(stableMs)")
            if stableMs >= stabilityDurationMs, let f = lastFullFrame {
                pendingResult = (f.base64, f.w, f.h, "success")
                semaphore.signal()
            }
        }
        prevDownsampled = curr

        // Deadline check.
        if Int(Date().timeIntervalSince(started) * 1000) >= timeoutMs {
            if let f = lastFullFrame {
                pendingResult = (f.base64, f.w, f.h, "timeout")
            }
            semaphore.signal()
        }
    }

    private func downsampledLuma(from sampleBuffer: CMSampleBuffer) -> [UInt8]? {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ci = CIImage(cvPixelBuffer: pb)
        let scaleX = Double(StableDetector.downsampledWidth) / Double(ci.extent.width)
        let scaleY = Double(StableDetector.downsampledHeight) / Double(ci.extent.height)
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        var bytes = [UInt8](repeating: 0,
                            count: StableDetector.downsampledWidth * StableDetector.downsampledHeight * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        ciContext.render(scaled,
                         toBitmap: &bytes,
                         rowBytes: StableDetector.downsampledWidth * 4,
                         bounds: CGRect(x: 0, y: 0,
                                        width: StableDetector.downsampledWidth,
                                        height: StableDetector.downsampledHeight),
                         format: .BGRA8,
                         colorSpace: cs)
        var luma = [UInt8](repeating: 0, count: StableDetector.totalPixels)
        for i in 0..<StableDetector.totalPixels {
            let b = Double(bytes[i * 4 + 0])
            let g = Double(bytes[i * 4 + 1])
            let r = Double(bytes[i * 4 + 2])
            luma[i] = UInt8(min(255.0, 0.299 * r + 0.587 * g + 0.114 * b))
        }
        return luma
    }
}

import Foundation
import AVFoundation
import Vision

final class GestureCapturer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session: DeskViewSession
    private let kind: GestureKind
    private let holdMs: Int
    private let timeoutMs: Int
    private let frameIntervalMs: Int = 67  // ~15fps

    private var holdCounter = GestureClassifier.HoldCounter()
    private let semaphore = DispatchSemaphore(value: 0)
    private var pendingResult: (base64: String, w: Int, h: Int, status: String)?
    private var captureError: DeskviewError?
    private let started = Date()
    private var lastFullFrame: (base64: String, w: Int, h: Int)?

    init(session: DeskViewSession, kind: GestureKind, holdMs: Int, timeoutMs: Int) {
        self.session = session
        self.kind = kind
        self.holdMs = holdMs
        self.timeoutMs = timeoutMs
    }

    func run() throws -> (base64: String, w: Int, h: Int, status: String, waitMs: Int, deviceName: String) {
        let output = try session.configureForStillCapture()
        let queue = DispatchQueue(label: "deskview.gesture")
        output.setSampleBufferDelegate(self, queue: queue)
        session.start()

        let deadline = DispatchTime.now() + .milliseconds(timeoutMs + 500)
        _ = semaphore.wait(timeout: deadline)
        session.stop()

        let waitMs = Int(Date().timeIntervalSince(started) * 1000)
        if let err = captureError { throw err }
        if let p = pendingResult { return (p.base64, p.w, p.h, p.status, waitMs, session.deviceName) }
        throw DeskviewError.timeout
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard pendingResult == nil else { return }

        if let png = try? ImageEncoder.pngBase64(from: sampleBuffer) {
            lastFullFrame = (png.base64, png.width, png.height)
        }

        // Run hand pose request synchronously on this frame.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            logStderr("gesture: vision error: \(error)")
            return
        }

        let matched: Bool
        if let observation = request.results?.first {
            let landmarks = mapLandmarks(observation: observation)
            matched = GestureClassifier.matches(kind, landmarks: landmarks)
        } else {
            matched = false
        }

        let consec = holdCounter.update(matched: matched)
        let heldMs = consec * frameIntervalMs
        if heldMs >= holdMs, let f = lastFullFrame {
            pendingResult = (f.base64, f.w, f.h, "success")
            semaphore.signal()
            return
        }

        if Int(Date().timeIntervalSince(started) * 1000) >= timeoutMs {
            // Gesture timeout per PRD returns isError, no frame.
            captureError = .timeout
            semaphore.signal()
        }
    }

    private func mapLandmarks(observation: VNHumanHandPoseObservation) -> HandLandmarks {
        var out = HandLandmarks()
        let mapping: [(HandJoint, VNHumanHandPoseObservation.JointName)] = [
            (.thumbTip, .thumbTip), (.thumbMCP, .thumbMP),
            (.indexTip, .indexTip), (.indexPIP, .indexPIP), (.indexMCP, .indexMCP),
            (.middleTip, .middleTip), (.middlePIP, .middlePIP), (.middleMCP, .middleMCP),
            (.ringTip, .ringTip), (.ringPIP, .ringPIP), (.ringMCP, .ringMCP),
            (.pinkyTip, .littleTip), (.pinkyPIP, .littlePIP), (.pinkyMCP, .littleMCP),
        ]
        for (ours, theirs) in mapping {
            if let p = try? observation.recognizedPoint(theirs), p.confidence > 0.3 {
                out[ours] = CGPoint(x: p.location.x, y: 1.0 - p.location.y)
            }
        }
        return out
    }
}

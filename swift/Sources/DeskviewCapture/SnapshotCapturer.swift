import Foundation
import AVFoundation

final class SnapshotCapturer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session: DeskViewSession
    private let semaphore = DispatchSemaphore(value: 0)
    private var captured: (base64: String, width: Int, height: Int)?
    private var captureError: DeskviewError?
    private var didCapture = false

    init(session: DeskViewSession) { self.session = session }

    func capture(timeoutMs: Int) throws -> (base64: String, width: Int, height: Int, deviceName: String, waitMs: Int) {
        let output = try session.configureForStillCapture()
        let queue = DispatchQueue(label: "deskview.capture")
        output.setSampleBufferDelegate(self, queue: queue)

        let start = Date()
        session.start()
        let deadline = DispatchTime.now() + .milliseconds(timeoutMs)
        let result = semaphore.wait(timeout: deadline)
        session.stop()

        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        if result == .timedOut {
            throw DeskviewError.captureFailed("no frame received within \(timeoutMs)ms")
        }
        if let err = captureError { throw err }
        guard let cap = captured else { throw DeskviewError.captureFailed("missing frame") }
        return (cap.base64, cap.width, cap.height, session.deviceName, elapsedMs)
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !didCapture else { return }
        didCapture = true
        do {
            captured = try ImageEncoder.pngBase64(from: sampleBuffer)
        } catch let err as DeskviewError {
            captureError = err
        } catch {
            captureError = .captureFailed("\(error)")
        }
        semaphore.signal()
    }
}

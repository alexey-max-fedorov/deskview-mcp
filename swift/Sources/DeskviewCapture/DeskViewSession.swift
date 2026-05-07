import Foundation
import AVFoundation

final class DeskViewSession {
    let session = AVCaptureSession()
    private(set) var device: AVCaptureDevice?
    private(set) var deviceName: String = "unknown"

    func discoverDevice() throws {
        // Tier 1: dedicated Desk View camera type.
        let primary = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.deskViewCamera],
            mediaType: .video,
            position: .unspecified
        )
        if let dv = primary.devices.first {
            self.device = dv
            self.deviceName = dv.localizedName
            logStderr("DeskViewSession: discovered primary device '\(dv.localizedName)'")
            return
        }

        // Tier 2: companion of a Continuity Camera.
        if #available(macOS 14.0, *) {
            let fallback = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.continuityCamera],
                mediaType: .video,
                position: .unspecified
            )
            if let main = fallback.devices.first,
               let companion = main.companionDeskViewCamera {
                self.device = companion
                self.deviceName = companion.localizedName
                logStderr("DeskViewSession: discovered fallback companion '\(companion.localizedName)' of '\(main.localizedName)'")
                return
            }
        }

        throw DeskviewError.noDevice
    }

    func ensureCameraAuthorization() throws {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let sem = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .video) { ok in
                granted = ok
                sem.signal()
            }
            sem.wait()
            if !granted { throw DeskviewError.permissionDenied }
        case .denied, .restricted:
            throw DeskviewError.permissionDenied
        @unknown default:
            throw DeskviewError.permissionDenied
        }
    }

    func configureForStillCapture() throws -> AVCaptureVideoDataOutput {
        guard let device = device else { throw DeskviewError.noDevice }
        session.beginConfiguration()
        session.sessionPreset = .high

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            session.commitConfiguration()
            throw DeskviewError.captureFailed("AVCaptureDeviceInput init failed: \(error)")
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw DeskviewError.captureFailed("cannot add device input")
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw DeskviewError.captureFailed("cannot add video data output")
        }
        session.addOutput(output)

        session.commitConfiguration()
        return output
    }

    func start() { session.startRunning() }
    func stop() { session.stopRunning() }
}

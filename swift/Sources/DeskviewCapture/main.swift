import Foundation
import ArgumentParser

struct Deskview: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deskview-capture",
        abstract: "Capture frames from the iPhone Continuity Camera Desk View.",
        subcommands: [Snapshot.self, Stable.self, Gesture.self]
    )
}

struct Snapshot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Capture one frame immediately."
    )

    func run() throws {
        let session = DeskViewSession()
        do {
            try session.ensureCameraAuthorization()
            try session.discoverDevice()
            let capturer = SnapshotCapturer(session: session)
            let cap = try capturer.capture(timeoutMs: 5000)
            let metadata = CaptureMetadata(
                width: cap.width,
                height: cap.height,
                captured_at: ISO8601DateFormatter().string(from: Date()),
                wait_duration_ms: cap.waitMs,
                device_name: cap.deviceName
            )
            emit(CaptureResult.success(image: cap.base64, metadata: metadata))
        } catch let err as DeskviewError {
            logStderr("snapshot failed: \(err.message)")
            emit(CaptureResult.error(err))
        } catch {
            logStderr("snapshot unexpected error: \(error)")
            emit(CaptureResult.error(.internalError("\(error)")))
        }
    }
}

struct Stable: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stable",
        abstract: "Capture once the scene is stable."
    )

    @Option(name: .long) var duration: Int = 3000
    @Option(name: .long) var timeout: Int = 300000
    @Option(name: .long) var sensitivity: String = "medium"

    func run() throws {
        let session = DeskViewSession()
        do {
            try session.ensureCameraAuthorization()
            try session.discoverDevice()
            let cap = StableCapturer(
                session: session,
                stabilityDurationMs: duration,
                timeoutMs: timeout,
                sensitivity: sensitivity
            )
            let r = try cap.run()
            let metadata = CaptureMetadata(
                width: r.w, height: r.h,
                captured_at: ISO8601DateFormatter().string(from: Date()),
                wait_duration_ms: r.waitMs,
                device_name: r.deviceName
            )
            if r.status == "success" {
                emit(CaptureResult.success(image: r.base64, metadata: metadata))
            } else {
                emit(CaptureResult.timeout(image: r.base64, metadata: metadata))
            }
        } catch let err as DeskviewError {
            logStderr("stable failed: \(err.message)")
            emit(CaptureResult.error(err))
        } catch {
            logStderr("stable unexpected error: \(error)")
            emit(CaptureResult.error(.internalError("\(error)")))
        }
    }
}

struct Gesture: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gesture",
        abstract: "Capture once a gesture is detected."
    )

    @Option(name: .long) var type: String
    @Option(name: .long) var hold: Int = 500
    @Option(name: .long) var timeout: Int = 300000

    func run() throws {
        logStderr("gesture: stub type=\(type) hold=\(hold) timeout=\(timeout)")
        let metadata = CaptureMetadata(
            width: 0, height: 0,
            captured_at: ISO8601DateFormatter().string(from: Date()),
            wait_duration_ms: 0,
            device_name: "stub"
        )
        emit(CaptureResult.success(image: "", metadata: metadata))
    }
}

Deskview.main()

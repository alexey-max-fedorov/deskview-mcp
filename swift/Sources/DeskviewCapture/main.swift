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
        logStderr("snapshot: stub")
        let metadata = CaptureMetadata(
            width: 0, height: 0,
            captured_at: ISO8601DateFormatter().string(from: Date()),
            wait_duration_ms: 0,
            device_name: "stub"
        )
        emit(CaptureResult.success(image: "", metadata: metadata))
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
        logStderr("stable: stub duration=\(duration) timeout=\(timeout) sensitivity=\(sensitivity)")
        let metadata = CaptureMetadata(
            width: 0, height: 0,
            captured_at: ISO8601DateFormatter().string(from: Date()),
            wait_duration_ms: 0,
            device_name: "stub"
        )
        emit(CaptureResult.success(image: "", metadata: metadata))
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

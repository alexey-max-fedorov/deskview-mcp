import Foundation

enum DeskviewError: Error {
    case noDevice
    case permissionDenied
    case captureFailed(String)
    case timeout
    case internalError(String)

    var code: String {
        switch self {
        case .noDevice: return "no_device"
        case .permissionDenied: return "permission_denied"
        case .captureFailed: return "capture_failed"
        case .timeout: return "timeout"
        case .internalError: return "internal"
        }
    }

    var message: String {
        switch self {
        case .noDevice:
            return "No Desk View camera found. Connect an iPhone via Continuity Camera and enable Desk View in Control Center."
        case .permissionDenied:
            return "Camera permission denied. Grant access in System Settings, Privacy and Security, Camera."
        case .captureFailed(let detail):
            return "Capture failed: \(detail)"
        case .timeout:
            return "Operation timed out."
        case .internalError(let detail):
            return "Internal error: \(detail)"
        }
    }
}

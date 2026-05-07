import Foundation

struct CaptureMetadata: Codable {
    let width: Int
    let height: Int
    let captured_at: String
    let wait_duration_ms: Int
    let device_name: String
}

struct CaptureResult: Codable {
    let status: String   // "success" | "timeout" | "error"
    let image_base64: String?
    let metadata: CaptureMetadata?
    let error_code: String?
    let error_message: String?

    static func success(image: String, metadata: CaptureMetadata) -> CaptureResult {
        CaptureResult(status: "success", image_base64: image, metadata: metadata,
                      error_code: nil, error_message: nil)
    }

    static func timeout(image: String?, metadata: CaptureMetadata?) -> CaptureResult {
        CaptureResult(status: "timeout", image_base64: image, metadata: metadata,
                      error_code: "timeout", error_message: "Timeout reached.")
    }

    static func error(_ err: DeskviewError) -> CaptureResult {
        CaptureResult(status: "error", image_base64: nil, metadata: nil,
                      error_code: err.code, error_message: err.message)
    }
}

func emit(_ result: CaptureResult) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
        let data = try encoder.encode(result)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    } catch {
        let fallback = "{\"status\":\"error\",\"error_code\":\"internal\",\"error_message\":\"json encode failed\"}\n"
        FileHandle.standardOutput.write(fallback.data(using: .utf8)!)
    }
}

func logStderr(_ msg: String) {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
}

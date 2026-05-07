import XCTest
@testable import DeskviewCapture

final class SmokeTests: XCTestCase {
    func testErrorCodes() {
        XCTAssertEqual(DeskviewError.noDevice.code, "no_device")
        XCTAssertEqual(DeskviewError.permissionDenied.code, "permission_denied")
        XCTAssertEqual(DeskviewError.timeout.code, "timeout")
    }

    func testCaptureResultEncodesAllFields() throws {
        let metadata = CaptureMetadata(
            width: 100, height: 50,
            captured_at: "2026-05-06T00:00:00Z",
            wait_duration_ms: 1234,
            device_name: "test"
        )
        let result = CaptureResult.success(image: "abc", metadata: metadata)
        let data = try JSONEncoder().encode(result)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"status\":\"success\""))
        XCTAssertTrue(json.contains("\"image_base64\":\"abc\""))
        XCTAssertTrue(json.contains("\"width\":100"))
    }
}

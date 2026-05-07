import Foundation
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

enum ImageEncoder {
    static let context = CIContext(options: nil)
    static let maxLongEdgePixels = 1280
    static let jpegQuality: CGFloat = 0.85

    static func jpegBase64(from sampleBuffer: CMSampleBuffer) throws -> (base64: String, width: Int, height: Int) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw DeskviewError.captureFailed("no pixel buffer in sample")
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let srcW = Int(CVPixelBufferGetWidth(pixelBuffer))
        let srcH = Int(CVPixelBufferGetHeight(pixelBuffer))

        let longEdge = max(srcW, srcH)
        let scale: CGFloat = longEdge > maxLongEdgePixels
            ? CGFloat(maxLongEdgePixels) / CGFloat(longEdge)
            : 1.0
        let scaled = scale < 1.0
            ? ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : ciImage
        let outW = Int((CGFloat(srcW) * scale).rounded())
        let outH = Int((CGFloat(srcH) * scale).rounded())

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            throw DeskviewError.captureFailed("CIContext.createCGImage failed")
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality]) else {
            throw DeskviewError.captureFailed("JPEG encode failed")
        }
        return (base64: jpegData.base64EncodedString(), width: outW, height: outH)
    }
}

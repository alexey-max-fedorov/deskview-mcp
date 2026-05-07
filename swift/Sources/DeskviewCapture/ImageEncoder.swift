import Foundation
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

enum ImageEncoder {
    static let context = CIContext(options: nil)

    static func pngBase64(from sampleBuffer: CMSampleBuffer) throws -> (base64: String, width: Int, height: Int) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw DeskviewError.captureFailed("no pixel buffer in sample")
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let width = Int(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int(CVPixelBufferGetHeight(pixelBuffer))

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw DeskviewError.captureFailed("CIContext.createCGImage failed")
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw DeskviewError.captureFailed("PNG encode failed")
        }
        return (base64: pngData.base64EncodedString(), width: width, height: height)
    }
}

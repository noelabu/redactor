import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum RedactorError: Error, Equatable {
    case decodeFailed
    case renderFailed
    case encodeFailed
}

/// A decoded image plus the DPI it was captured at, so re-encoding keeps its point size.
public struct SourceImage: @unchecked Sendable {
    public let cgImage: CGImage
    public let dpi: Double

    public init(cgImage: CGImage, dpi: Double = 72) {
        self.cgImage = cgImage
        self.dpi = dpi
    }

    public init(pngData: Data) throws {
        guard let src = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw RedactorError.decodeFailed }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        self.cgImage = image
        self.dpi = (props?[kCGImagePropertyDPIWidth] as? Double) ?? 72
    }
}

public enum ImageRedactor {
    /// Draws the image with an opaque black rectangle over every enabled box.
    public static func render(_ image: CGImage, boxes: [RedactionBox]) throws -> CGImage {
        let w = image.width, h = image.height
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw RedactorError.renderFailed }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Boxes are top-left origin; flip so they land where the text was.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        for box in boxes where box.enabled {
            ctx.fill(box.rect)
        }
        guard let out = ctx.makeImage() else { throw RedactorError.renderFailed }
        return out
    }

    /// Encodes `image` as PNG keeping only image data, size, DPI and colour chunks. ImageIO adds an
    /// eXIf chunk of its own, so the output is filtered through `PNGChunks.stripMetadata`.
    public static func pngData(_ image: CGImage, dpi: Double) throws -> Data {
        try PNGChunks.stripMetadata(encode(image, dpi: dpi))
    }

    private static func encode(_ image: CGImage, dpi: Double) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw RedactorError.encodeFailed }
        let props: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw RedactorError.encodeFailed }
        return data as Data
    }
}

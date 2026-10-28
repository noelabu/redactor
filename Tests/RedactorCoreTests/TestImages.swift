import CoreGraphics
import CoreText
import Foundation
@testable import RedactorCore

/// Test images with known text. Rects are in pixels, top-left origin.
enum TestImages {
    static func solid(width: Int, height: Int, gray: CGFloat) -> CGImage {
        let ctx = context(width: width, height: height)
        ctx.setFillColor(CGColor(gray: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// RGBA bytes of the pixel at (x, y), top-left origin.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        let ctx = context(width: image.width, height: image.height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let offset = y * ctx.bytesPerRow + x * 4
        return (0..<4).map { bytes[offset + $0] }
    }

    struct Rendered {
        let image: CGImage
        /// Rect of each requested substring, keyed by the substring.
        let rects: [String: CGRect]
    }

    /// Draws each line in black on white and records the rect of every substring in `mark`.
    static func lines(_ lines: [String], mark: [String], fontSize: CGFloat, scale: CGFloat = 2) -> Rendered {
        form(lines.map { [$0] }, mark: mark, fontSize: fontSize, scale: scale)
    }

    /// Draws a grid: each row's cells start at fixed columns `columnWidth` points apart,
    /// like a printed form with the label in one box and the value in the next.
    static func form(_ rows: [[String]], mark: [String], fontSize: CGFloat, scale: CGFloat = 2, columnWidth: CGFloat = 0, lineSpacing: CGFloat = 1.8) -> Rendered {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize * scale, nil)
        let lineHeight = fontSize * scale * lineSpacing
        let margin = 20 * scale
        let columns = rows.map(\.count).max() ?? 1
        let width = Int(fontSize * scale * 24 + columnWidth * scale * CGFloat(columns - 1) + margin * 2)
        let height = Int(CGFloat(rows.count) * lineHeight + margin * 2)
        let ctx = context(width: width, height: height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        var rects: [String: CGRect] = [:]
        for (i, row) in rows.enumerated() {
          for (col, text) in row.enumerated() {
            let x = margin + CGFloat(col) * columnWidth * scale
            let attr = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                // Dark blue, not black, so leftover text can be told apart from redaction boxes.
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0.05, green: 0.1, blue: 0.45, alpha: 1),
            ])
            let line = CTLineCreateWithAttributedString(attr)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            // Baseline in CG (bottom-left) coordinates.
            let baseline = CGFloat(height) - margin - CGFloat(i) * lineHeight - ascent
            ctx.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(line, ctx)

            for target in mark {
                let r = (text as NSString).range(of: target)
                guard r.location != NSNotFound else { continue }
                let x0 = CTLineGetOffsetForStringIndex(line, r.location, nil)
                let x1 = CTLineGetOffsetForStringIndex(line, NSMaxRange(r), nil)
                let top = CGFloat(height) - (baseline + ascent)
                rects[target] = CGRect(x: x + x0, y: top, width: x1 - x0, height: ascent + descent)
            }
          }
        }
        return Rendered(image: ctx.makeImage()!, rects: rects)
    }

    private static func context(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }
}

/// Fraction of pixels in `rect` of `image` that are still visible text: neither near-white
/// background nor the pure black of a redaction box.
func leakedInk(in rect: CGRect, of image: CGImage) -> Double {
    let w = image.width, h = image.height
    let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
    let r = rect.integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
    var leaked = 0, total = 0
    for y in Int(r.minY)..<Int(r.maxY) {
        for x in Int(r.minX)..<Int(r.maxX) {
            let o = y * ctx.bytesPerRow + x * 4
            let maxChannel = max(bytes[o], bytes[o + 1], bytes[o + 2])
            if maxChannel < 230 && maxChannel > 8 { leaked += 1 }
            total += 1
        }
    }
    return total == 0 ? 0 : Double(leaked) / Double(total)
}

/// Fraction of `target`'s area covered by the union of enabled boxes (sampled on a grid).
func coverage(of target: CGRect, by boxes: [RedactionBox]) -> Double {
    let steps = 20
    var hit = 0
    for i in 0..<steps {
        for j in 0..<steps {
            let p = CGPoint(
                x: target.minX + target.width * (CGFloat(i) + 0.5) / CGFloat(steps),
                y: target.minY + target.height * (CGFloat(j) + 0.5) / CGFloat(steps)
            )
            if boxes.contains(where: { $0.enabled && $0.rect.contains(p) }) { hit += 1 }
        }
    }
    return Double(hit) / Double(steps * steps)
}

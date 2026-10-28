import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
@testable import RedactorCore

/// Draws the before/after images in docs/images with the real engine on made-up documents.
/// Opt-in: REDACTOR_README_OUT=docs/images swift test --filter ReadmeImageTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["REDACTOR_README_OUT"] != nil))
struct ReadmeImageTests {
    static let scale: CGFloat = 2
    static let navy = CGColor(red: 0.09, green: 0.16, blue: 0.36, alpha: 1)
    static let ink = CGColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
    static let muted = CGColor(red: 0.42, green: 0.45, blue: 0.5, alpha: 1)
    static let rule = CGColor(red: 0.88, green: 0.89, blue: 0.91, alpha: 1)

    var outDir: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["REDACTOR_README_OUT"]!) }

    @Test func form() async throws {
        let rows: [(String, String)] = [
            ("Full Name", "Maria Clara Santos"),
            ("Date of Birth", "March 14, 1992"),
            ("TIN", "123-456-789-000"),
            ("SSS No.", "34-1234567-8"),
            ("PhilHealth No.", "12-345678901-2"),
            ("Address", "45 Mabini St., Brgy. Poblacion, Makati City"),
            ("Mobile", "0917 555 1234"),
            ("Email", "maria.santos@gmail.com"),
            ("Position", "Senior Accountant"),
            ("Department", "Finance"),
        ]
        let w = 760, rowH: CGFloat = 46, top: CGFloat = 96
        let h = Int(top + CGFloat(rows.count) * rowH + 30)
        let image = Self.draw(width: w, height: h) { c in
            c.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: 64), Self.navy)
            c.text("EMPLOYEE INFORMATION SHEET", x: 28, y: 22, size: 19, color: CGColor(gray: 1, alpha: 1), bold: true)
            for (i, row) in rows.enumerated() {
                let y = top + CGFloat(i) * rowH
                c.text(row.0, x: 28, y: y, size: 15, color: Self.muted)
                c.text(row.1, x: 230, y: y, size: 16, color: Self.ink)
                c.fill(CGRect(x: 28, y: y + 32, width: CGFloat(w) - 56, height: 1), Self.rule)
            }
        }
        try await writePair(image, name: "form")
    }

    @Test func chat() async throws {
        let messages: [(String, Bool)] = [
            ("Hi po! Sending my details for the loan application", false),
            ("Sure, please send your TIN and contact info", true),
            ("TIN: 987-654-321-000", false),
            ("Mobile: 0918 222 3344", false),
            ("Email: jdelacruz88@yahoo.com", false),
            ("Got it, thank you! We'll call you tomorrow", true),
        ]
        let w = 640, bubbleH: CGFloat = 44, gap: CGFloat = 14, top: CGFloat = 78
        let h = Int(top + CGFloat(messages.count) * (bubbleH + gap) + 20)
        let image = Self.draw(width: w, height: h) { c in
            c.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: 58), CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1))
            c.text("Juan Dela Cruz", x: 24, y: 18, size: 18, color: Self.ink, bold: true)
            for (i, m) in messages.enumerated() {
                let y = top + CGFloat(i) * (bubbleH + gap)
                let width = c.width(m.0, size: 15) + 32
                let x = m.1 ? CGFloat(w) - 24 - width : 24
                let fill = m.1 ? CGColor(red: 0.2, green: 0.47, blue: 0.96, alpha: 1) : CGColor(red: 0.91, green: 0.92, blue: 0.94, alpha: 1)
                c.roundRect(CGRect(x: x, y: y, width: width, height: bubbleH), radius: 18, fill)
                c.text(m.0, x: x + 16, y: y + 12, size: 15, color: m.1 ? CGColor(gray: 1, alpha: 1) : Self.ink)
            }
        }
        try await writePair(image, name: "chat")
    }

    /// Runs the engine (with the AI check when Apple Intelligence is on) and writes
    /// them side by side to `<name>.png`.
    private func writePair(_ before: CGImage, name: String) async throws {
        let ai: (any LinePIIDetector)? = FoundationModelsDetector.unavailableReason == nil ? FoundationModelsDetector() : nil
        let result = try await RedactionEngine.run(SourceImage(cgImage: before, dpi: 144), ai: ai)
        let after = try SourceImage(pngData: result.redactedPNG).cgImage
        print("README \(name): \(result.boxes.count) boxes, ai \(result.aiStatus)")
        try Self.write(Self.sideBySide(before, after), to: outDir.appendingPathComponent("\(name).png"))
    }

    /// Both images on a light background with "Screenshot" and "Copied by Redactor" captions.
    static func sideBySide(_ a: CGImage, _ b: CGImage) -> CGImage {
        let pad: CGFloat = 40, caption: CGFloat = 44, arrow: CGFloat = 70
        let iw = CGFloat(a.width) / scale, ih = CGFloat(a.height) / scale
        let w = Int(pad * 2 + iw * 2 + arrow), h = Int(pad * 2 + caption + ih)
        return draw(width: w, height: h, background: CGColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)) { c in
            for (i, (img, label)) in [(a, "Screenshot"), (b, "Copied by Redactor")].enumerated() {
                let x = pad + CGFloat(i) * (iw + arrow)
                c.text(label, x: x, y: pad, size: 17, color: muted, bold: true)
                let frame = CGRect(x: x, y: pad + caption, width: iw, height: ih)
                c.shadowed(frame, radius: 10)
                c.image(img, in: frame, radius: 10)
            }
            c.text("→", x: pad + iw + arrow / 2 - 13, y: pad + caption + ih / 2 - 18, size: 32, color: muted)
        }
    }

    // MARK: Drawing in points with a top-left origin.

    struct Canvas {
        let ctx: CGContext
        let height: CGFloat

        private func flip(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * scale, y: (height - r.maxY) * scale, width: r.width * scale, height: r.height * scale)
        }

        func fill(_ r: CGRect, _ color: CGColor) {
            ctx.setFillColor(color)
            ctx.fill(flip(r))
        }

        func roundRect(_ r: CGRect, radius: CGFloat, _ color: CGColor) {
            ctx.setFillColor(color)
            ctx.addPath(CGPath(roundedRect: flip(r), cornerWidth: radius * scale, cornerHeight: radius * scale, transform: nil))
            ctx.fillPath()
        }

        func shadowed(_ r: CGRect, radius: CGFloat) {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -3 * scale), blur: 14 * scale, color: CGColor(gray: 0, alpha: 0.18))
            roundRect(r, radius: radius, CGColor(gray: 1, alpha: 1))
            ctx.restoreGState()
        }

        func image(_ img: CGImage, in r: CGRect, radius: CGFloat) {
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: flip(r), cornerWidth: radius * scale, cornerHeight: radius * scale, transform: nil))
            ctx.clip()
            ctx.interpolationQuality = .high
            ctx.draw(img, in: flip(r))
            ctx.restoreGState()
        }

        private func line(_ s: String, size: CGFloat, color: CGColor, bold: Bool) -> CTLine {
            let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size * scale, nil)
            return CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]))
        }

        func width(_ s: String, size: CGFloat) -> CGFloat {
            CGFloat(CTLineGetTypographicBounds(line(s, size: size, color: ink, bold: false), nil, nil, nil)) / scale
        }

        /// Draws `s` with the top of its capitals near `y`.
        func text(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat, color: CGColor, bold: Bool = false) {
            let l = line(s, size: size, color: color, bold: bold)
            ctx.textPosition = CGPoint(x: x * scale, y: (height - y - size) * scale)
            CTLineDraw(l, ctx)
        }
    }

    static func draw(width: Int, height: Int, background: CGColor = CGColor(gray: 1, alpha: 1), _ body: (Canvas) -> Void) -> CGImage {
        let ctx = CGContext(
            data: nil, width: Int(CGFloat(width) * scale), height: Int(CGFloat(height) * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        body(Canvas(ctx: ctx, height: CGFloat(height)))
        return ctx.makeImage()!
    }

    static func write(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ImageRedactor.pngData(image, dpi: 144).write(to: url)
    }
}

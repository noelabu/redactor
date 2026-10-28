import CoreGraphics
import Foundation
import Testing
@testable import RedactorCore

/// Renders known text, runs the real Vision OCR + detectors + renderer, and checks what got covered.
@Suite struct EndToEndOCRTests {
    static let lines = [
        "Email jane.doe@example.com",
        "Call (415) 555-0132",
        "Card 4111 1111 1111 1111",
        "Hello world",
    ]
    static let pii = ["jane.doe@example.com", "(415) 555-0132", "4111 1111 1111 1111"]

    // An invalid card number like 4111 1111 1111 1112 is still redacted: it has the shape of a PhilSys PSN.
    @Test func redactsPIIAndOnlyPII() async throws {
        let rendered = TestImages.lines(Self.lines, mark: Self.pii + ["Hello world", "Email", "Call"], fontSize: 28)
        let result = try await RedactionEngine.run(SourceImage(cgImage: rendered.image, dpi: 144))
        let out = try SourceImage(pngData: result.redactedPNG)

        for text in Self.pii {
            let rect = try #require(rendered.rects[text])
            #expect(coverage(of: rect, by: result.boxes) >= 0.8, "\(text) mostly uncovered")
            #expect(leakedInk(in: rect, of: out.cgImage) < 0.005, "\(text) still visible")
        }
        #expect(coverage(of: rendered.rects["Hello world"]!, by: result.boxes) == 0)
        // Sub-line boxes: the label words stay mostly visible.
        #expect(coverage(of: rendered.rects["Email"]!, by: result.boxes) < 0.5)
        #expect(coverage(of: rendered.rects["Call"]!, by: result.boxes) < 0.5)

        // The saved PNG is actually black over the PII.
        #expect(out.dpi == 144)
        for text in Self.pii {
            let r = rendered.rects[text]!
            #expect(TestImages.pixel(out.cgImage, x: Int(r.midX), y: Int(r.midY)) == [0, 0, 0, 255])
        }
    }

    @Test func cleanImageGetsNoBoxes() async throws {
        let rendered = TestImages.lines(["Quarterly summary", "Nothing sensitive here"], mark: [], fontSize: 28)
        let result = try await RedactionEngine.run(SourceImage(cgImage: rendered.image))
        #expect(result.boxes.isEmpty)
    }

    /// Measures where OCR gives out on small 1x text; known to be weaker.
    @Test(.disabled("known limit: small 1x text"))
    func smallTextAtOneX() async throws {
        let rendered = TestImages.lines(["Email jane.doe@example.com"], mark: ["jane.doe@example.com"], fontSize: 11, scale: 1)
        let result = try await RedactionEngine.run(SourceImage(cgImage: rendered.image))
        #expect(coverage(of: rendered.rects["jane.doe@example.com"]!, by: result.boxes) >= 0.95)
    }
}

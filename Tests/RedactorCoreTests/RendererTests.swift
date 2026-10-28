import CoreGraphics
import Foundation
import Testing
@testable import RedactorCore

@Suite struct RendererTests {
    @Test func fillsEnabledBoxesBlackAndLeavesTheRest() throws {
        let src = TestImages.solid(width: 100, height: 80, gray: 1)
        let boxes = [
            RedactionBox(rect: CGRect(x: 10, y: 5, width: 20, height: 10), kind: .email),
            RedactionBox(rect: CGRect(x: 50, y: 50, width: 20, height: 10), kind: .phone, enabled: false),
        ]
        let out = try ImageRedactor.render(src, boxes: boxes)

        // Top-left origin: (15, 8) is inside the first box.
        #expect(TestImages.pixel(out, x: 15, y: 8) == [0, 0, 0, 255])
        // Disabled box stays white.
        #expect(TestImages.pixel(out, x: 55, y: 55) == [255, 255, 255, 255])
        // Mirror of the first box (bottom-left reading) stays white, proving the flip.
        #expect(TestImages.pixel(out, x: 15, y: 70) == [255, 255, 255, 255])
    }

    @Test func pngRoundTripKeepsDPI() throws {
        let src = TestImages.solid(width: 10, height: 10, gray: 0.5)
        let data = try ImageRedactor.pngData(src, dpi: 144)
        let decoded = try SourceImage(pngData: data)
        #expect(decoded.dpi == 144)
        #expect(decoded.cgImage.width == 10)
    }

    @Test func decodeRejectsGarbage() {
        #expect(throws: RedactorError.decodeFailed) { try SourceImage(pngData: Data([1, 2, 3])) }
    }
}

@Suite struct NamingTests {
    let dir = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
    // 2026-10-27 17:42:10 UTC
    let date = Date(timeIntervalSince1970: 1_793_122_930)
    let utc = TimeZone(identifier: "UTC")!

    @Test func macOSStyleName() {
        let url = ScreenshotNaming.fileURL(in: dir, date: date, locale: Locale(identifier: "en_US"), timeZone: utc, exists: { _ in false })
        #expect(url.lastPathComponent == "Screenshot 2026-10-27 at 5.42.10\u{202F}PM.png")
    }

    @Test func addsSuffixOnCollision() {
        var taken: Set<String> = []
        let first = ScreenshotNaming.fileURL(in: dir, date: date, locale: Locale(identifier: "en_US"), timeZone: utc, exists: { _ in false })
        taken.insert(first.lastPathComponent)
        taken.insert(first.deletingPathExtension().lastPathComponent + " (2).png")
        let url = ScreenshotNaming.fileURL(in: dir, date: date, locale: Locale(identifier: "en_US"), timeZone: utc, exists: { taken.contains($0.lastPathComponent) })
        #expect(url.lastPathComponent.hasSuffix(" (3).png"))
    }

    @Test func fallsBackToDesktopWhenUnset() {
        #expect(ScreenshotNaming.outputDirectory(configured: nil).lastPathComponent == "Desktop")
        #expect(ScreenshotNaming.outputDirectory(configured: "/no/such/dir").lastPathComponent == "Desktop")
    }

    @Test func usesConfiguredDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(ScreenshotNaming.outputDirectory(configured: tmp.path).standardizedFileURL == tmp.standardizedFileURL)
    }
}

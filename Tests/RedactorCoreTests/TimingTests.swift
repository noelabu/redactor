import Foundation
import Testing
@testable import RedactorCore

/// Opt-in: REDACTOR_TIMING_IMAGE=/path/to.png swift test --filter TimingTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["REDACTOR_TIMING_IMAGE"] != nil))
struct TimingTests {
    @Test func stages() async throws {
        let path = ProcessInfo.processInfo.environment["REDACTOR_TIMING_IMAGE"]!
        let source = try SourceImage(pngData: Data(contentsOf: URL(fileURLWithPath: path)))
        func time<T>(_ label: String, _ body: () async throws -> T) async rethrows -> T {
            let start = Date()
            let value = try await body()
            print(String(format: "TIMING %@ %.2fs", label, Date().timeIntervalSince(start)))
            return value
        }
        print("TIMING image \(source.cgImage.width)x\(source.cgImage.height)")
        let page = try await time("ocr") { try OCRPage.recognize(source.cgImage) }
        print("TIMING lines \(page.lines.count), chars \(page.lines.map(\.text.count).reduce(0, +))")
        _ = await time("rules") { page.detect(pipeline: .standard) }
        FoundationModelsDetector.prewarm()
        let ai = try await time("ai") { try await FoundationModelsDetector().detect(lines: page.lines.map(\.text)) }
        print("TIMING ai chunks \(FoundationModelsDetector.chunks(page.lines.map(\.text)).count), skipped \(ai.skippedLines)")
        _ = try await time("ai again") { try await FoundationModelsDetector().detect(lines: page.lines.map(\.text)) }
        _ = try await time("render") { try ImageRedactor.render(source.cgImage, boxes: []) }
        _ = try await time("full run") { try await RedactionEngine.run(source, ai: FoundationModelsDetector()) }
        _ = try await time("full run no ai") { try await RedactionEngine.run(source) }
    }
}

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import RedactorCore

@Suite struct FindingMatcherTests {
    let lines = ["Payslip for October", "Prepared by Maria Santos", "Employee: Juan Dela Cruz, juan again"]

    @Test func matchesOnReportedLine() {
        let d = FindingMatcher.match([ReportedFinding(line: 1, text: "Maria Santos", kind: .name)], lines: lines)
        #expect(d == [LineDetection(line: 1, range: NSRange(location: 12, length: 12), kind: .name)])
    }

    @Test func caseInsensitiveAndAllOccurrences() {
        let d = FindingMatcher.match([ReportedFinding(line: 2, text: "JUAN", kind: .name)], lines: lines)
        #expect(d.map(\.range.location) == [10, 26])
    }

    @Test func fallsBackToAnyLineWhenLineNumberIsWrong() {
        let d = FindingMatcher.match([ReportedFinding(line: 0, text: "Juan Dela Cruz", kind: .name)], lines: lines)
        #expect(d.map(\.line) == [2])
    }

    @Test func dropsTextNotOnThePage() {
        let findings = [
            ReportedFinding(line: 1, text: "Pedro Penduko", kind: .name),
            ReportedFinding(line: 7, text: "Maria", kind: .name),
        ]
        #expect(FindingMatcher.match([findings[0]], lines: lines).isEmpty)
        // Out-of-range line numbers still match elsewhere on the page.
        #expect(FindingMatcher.match([findings[1]], lines: lines).map(\.line) == [1])
    }

    @Test func dropsTooShortText() {
        #expect(FindingMatcher.match([ReportedFinding(line: 1, text: " M ", kind: .name)], lines: lines).isEmpty)
    }

    @Test func chunksStayUnderLimit() {
        let lines = Array(repeating: String(repeating: "x", count: 900), count: 7)
        let chunks = FoundationModelsDetector.chunks(lines)
        #expect(chunks.flatMap { $0 } == Array(0..<7))
        #expect(chunks.allSatisfy { $0.count <= 2 })
    }
}

/// A stand-in for the on-device model.
struct FakeAI: LinePIIDetector {
    var names: [String] = []
    var error: (any Error)?

    func detect(lines: [String]) async throws -> LinePIIResult {
        if let error { throw error }
        return LinePIIResult(detections: FindingMatcher.match(
            lines.indices.flatMap { i in names.map { ReportedFinding(line: i, text: $0, kind: .name) } },
            lines: lines
        ))
    }
}

@Suite struct AILayerTests {
    static let rows = [["Prepared by Maria Santos"], ["Email jane.doe@example.com"]]

    @Test func aiAddsBoxesRulesMiss() async throws {
        let rendered = TestImages.form(Self.rows, mark: ["Maria Santos", "jane.doe@example.com", "Prepared"], fontSize: 24)
        let result = try await RedactionEngine.run(SourceImage(cgImage: rendered.image), ai: FakeAI(names: ["Maria Santos"]))
        let out = try SourceImage(pngData: result.redactedPNG).cgImage

        #expect(result.aiStatus == .used(skippedLines: 0))
        #expect(leakedInk(in: rendered.rects["Maria Santos"]!, of: out) < 0.005)
        #expect(leakedInk(in: rendered.rects["jane.doe@example.com"]!, of: out) < 0.005)
        #expect(coverage(of: rendered.rects["Prepared"]!, by: result.boxes) == 0)
    }

    @Test func rulesStillApplyWhenAIFails() async throws {
        struct Boom: Error {}
        let rendered = TestImages.form(Self.rows, mark: ["Maria Santos", "jane.doe@example.com"], fontSize: 24)
        let result = try await RedactionEngine.run(SourceImage(cgImage: rendered.image), ai: FakeAI(error: Boom()))
        let out = try SourceImage(pngData: result.redactedPNG).cgImage

        guard case .failed = result.aiStatus else { Issue.record("expected .failed, got \(result.aiStatus)"); return }
        #expect(leakedInk(in: rendered.rects["jane.doe@example.com"]!, of: out) < 0.005)
        #expect(coverage(of: rendered.rects["Maria Santos"]!, by: result.boxes) == 0)
    }

    @Test func reportsRuleBoxesBeforeAI() async throws {
        final class Log: @unchecked Sendable {
            let lock = NSLock()
            var events: [String] = []
            func add(_ e: String) { lock.withLock { events.append(e) } }
        }
        struct RecordingAI: LinePIIDetector {
            let log: Log
            func detect(lines: [String]) async throws -> LinePIIResult {
                log.add("ai")
                return LinePIIResult(detections: [])
            }
        }
        let log = Log()
        let rendered = TestImages.form(Self.rows, mark: [], fontSize: 24)
        _ = try await RedactionEngine.run(SourceImage(cgImage: rendered.image), ai: RecordingAI(log: log)) { progress in
            switch progress {
            case .rulesDone(let boxes): log.add("rules:\(boxes.count)")
            case .aiChecking: log.add("aiChecking")
            case .doubleChecking: log.add("doubleChecking")
            }
        }
        #expect(log.events == ["rules:1", "aiChecking", "ai", "doubleChecking"])
    }

    @Test func reportsUnavailableReason() async throws {
        let rendered = TestImages.form(Self.rows, mark: [], fontSize: 24)
        let ai = FakeAI(error: LinePIIDetectorUnavailable("Apple Intelligence is off"))
        let result = try await RedactionEngine.run(SourceImage(cgImage: rendered.image), ai: ai)
        #expect(result.aiStatus == .unavailable("Apple Intelligence is off"))
    }
}

@Suite struct DoubleCheckTests {
    /// Fires on "REF-…" codes only when the line doesn't also contain "Header", so the first pass
    /// misses it; once the AI boxes "Header", the double-check pass reads the code on its own.
    struct ContextSensitive: Detector {
        func detect(in text: String) -> [Detection] {
            guard !text.contains("Header") else { return [] }
            let r = (text as NSString).range(of: #"REF-\d+"#, options: .regularExpression)
            return r.location == NSNotFound ? [] : [Detection(kind: .idNumber, range: r)]
        }
    }

    @Test func boxesTextStillReadableAfterFirstPass() async throws {
        let rendered = TestImages.form([["Header REF-778812"]], mark: ["REF-778812"], fontSize: 28)
        let pipeline = DetectionPipeline(detectors: [ContextSensitive()])
        let result = try await RedactionEngine.run(
            SourceImage(cgImage: rendered.image), pipeline: pipeline, ai: FakeAI(names: ["Header"])
        )
        let out = try SourceImage(pngData: result.redactedPNG).cgImage

        #expect(result.boxesAddedByDoubleCheck >= 1)
        #expect(leakedInk(in: rendered.rects["REF-778812"]!, of: out) < 0.005)
    }

    @Test func noExtraBoxesWhenFirstPassIsClean() async throws {
        let rendered = TestImages.form([["Name: Juan Dela Cruz"], ["TIN: 123-456-789-000"]], mark: [], fontSize: 24)
        let result = try await RedactionEngine.run(SourceImage(cgImage: rendered.image))
        #expect(result.boxesAddedByDoubleCheck == 0)
    }
}

@Suite struct OutputMetadataTests {
    /// Reads the chunk types of a PNG file (after the 8-byte signature: length, type, data, CRC).
    static func chunkTypes(_ png: Data) -> [String] {
        let bytes = [UInt8](png)
        var types: [String] = []
        var i = 8
        while i + 8 <= bytes.count {
            let length = Int(bytes[i]) << 24 | Int(bytes[i + 1]) << 16 | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            types.append(String(decoding: bytes[(i + 4)..<(i + 8)], as: UTF8.self))
            i += 12 + length
        }
        return types
    }

    // ImageIO reports synthesized Exif/TIFF dictionaries (size, DPI) for any PNG, so check the
    // actual chunks: only image data, size, DPI and colour information may be written.
    @Test func savedPNGCarriesOnlyImageChunks() throws {
        let png = try ImageRedactor.pngData(TestImages.solid(width: 20, height: 20, gray: 1), dpi: 144)
        let types = Self.chunkTypes(png)
        #expect(types.first == "IHDR")
        #expect(types.last == "IEND")
        #expect(Set(types).isSubset(of: PNGChunks.allowed), "unexpected chunks: \(Set(types).subtracting(PNGChunks.allowed))")
        // Still decodes, with its DPI.
        #expect(try SourceImage(pngData: png).dpi == 144)
    }

    @Test func stripRejectsTruncatedPNG() throws {
        let png = try ImageRedactor.pngData(TestImages.solid(width: 20, height: 20, gray: 1), dpi: 72)
        #expect(throws: RedactorError.encodeFailed) { try PNGChunks.stripMetadata(png.prefix(png.count - 20)) }
        #expect(throws: RedactorError.encodeFailed) { try PNGChunks.stripMetadata(Data([1, 2, 3])) }
    }

    @Test func redactedCapturePNGDropsSourceMetadata() async throws {
        // A source PNG with a text chunk, as some capture tools write.
        let data = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        let props: [CFString: Any] = [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: "secret note"]]
        CGImageDestinationAddImage(dest, TestImages.lines(["Hello"], mark: [], fontSize: 20).image, props as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        #expect(Self.chunkTypes(data as Data).contains { ["tEXt", "iTXt", "zTXt"].contains($0) })

        let result = try await RedactionEngine.run(try SourceImage(pngData: data as Data))
        #expect(!Self.chunkTypes(result.redactedPNG).contains { ["tEXt", "iTXt", "zTXt", "eXIf", "tIME"].contains($0) })
    }
}

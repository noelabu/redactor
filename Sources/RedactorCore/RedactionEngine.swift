import CoreGraphics
import Foundation

/// What happened with the AI layer for one capture.
public enum AIStatus: Sendable, Equatable {
    case off
    /// Ran; `skippedLines` couldn't be read (e.g. Filipino, which the model doesn't support).
    case used(skippedLines: Int)
    case unavailable(String)
    case failed(String)
}

public struct RedactionResult: Sendable {
    public let boxes: [RedactionBox]
    public let redactedPNG: Data
    public let aiStatus: AIStatus
    /// Boxes added by the double-check pass (PII still readable after the first redaction).
    public let boxesAddedByDoubleCheck: Int
}

/// Stages reported while `run` works, so the UI can show progress.
public enum RedactionProgress: Sendable {
    /// The rules' boxes, available before the AI check starts.
    case rulesDone([RedactionBox])
    case aiChecking
    case doubleChecking
}

public enum RedactionEngine {
    /// Finds PII in `source`, boxes it, then re-reads the redacted image up to `doubleCheckPasses`
    /// times and boxes anything still readable. Throws rather than ever returning the original.
    public static func run(
        _ source: SourceImage,
        pipeline: DetectionPipeline = .standard,
        ai: (any LinePIIDetector)? = nil,
        doubleCheckPasses: Int = 2,
        progress: (@Sendable (RedactionProgress) -> Void)? = nil
    ) async throws -> RedactionResult {
        let image = source.cgImage
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        func boxes(_ located: [LocatedDetection]) -> [RedactionBox] {
            located.map { RedactionBox(rect: BoxOps.pad($0.rect, in: bounds), kind: $0.kind) }
        }

        let page = try OCRPage.recognize(image)
        var located = page.detect(pipeline: pipeline)
        progress?(.rulesDone(BoxOps.merge(boxes(located))))

        var aiStatus = AIStatus.off
        if let ai {
            progress?(.aiChecking)
            do {
                let found = try await ai.detect(lines: page.lines.map(\.text))
                located += found.detections.compactMap { page.locate($0.kind, $0.range, onLine: $0.line) }
                aiStatus = .used(skippedLines: found.skippedLines)
            } catch let error as LinePIIDetectorUnavailable {
                aiStatus = .unavailable(error.reason)
            } catch {
                aiStatus = .failed(String(describing: error))
            }
        }

        var all = BoxOps.merge(boxes(located))
        var redacted = try ImageRedactor.render(image, boxes: all)

        // Double-check: anything a detector can still read in the redacted image gets another box.
        // Label neighbours are skipped here: once a value is blacked out, its label stands alone
        // and would otherwise claim the next line.
        var added = 0
        if doubleCheckPasses > 0 { progress?(.doubleChecking) }
        for _ in 0..<doubleCheckPasses {
            let leftover = try OCRPage.recognize(redacted).detect(pipeline: pipeline, labelNeighbors: false)
            guard !leftover.isEmpty else { break }
            added += leftover.count
            all = BoxOps.merge(all + boxes(leftover))
            redacted = try ImageRedactor.render(image, boxes: all)
        }

        let png = try ImageRedactor.pngData(redacted, dpi: source.dpi)
        return RedactionResult(boxes: all, redactedPNG: png, aiStatus: aiStatus, boxesAddedByDoubleCheck: added)
    }

    public static func render(_ source: SourceImage, boxes: [RedactionBox]) throws -> Data {
        let out = try ImageRedactor.render(source.cgImage, boxes: boxes)
        return try ImageRedactor.pngData(out, dpi: source.dpi)
    }
}

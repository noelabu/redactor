import CoreGraphics
import Foundation
import Vision

/// A detection located on the image, in pixels with a top-left origin.
public struct LocatedDetection: Sendable, Equatable {
    public let kind: PIIKind
    public let text: String
    public let rect: CGRect
}

/// The OCR result for one image: its text lines, plus the ability to box any part of a line.
/// Vision objects are read-only after recognition, so sharing the page across tasks is safe.
public final class OCRPage: @unchecked Sendable {
    public struct Line: Sendable {
        public let text: String
        /// Whole-line rect in pixels, top-left origin.
        public let rect: CGRect
    }

    public let lines: [Line]
    private let candidates: [VNRecognizedText]
    private let width: Int
    private let height: Int

    private init(lines: [Line], candidates: [VNRecognizedText], width: Int, height: Int) {
        self.lines = lines
        self.candidates = candidates
        self.width = width
        self.height = height
    }

    public static func recognize(_ image: CGImage) throws -> OCRPage {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction "fixes" emails and digit runs.
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0

        try VNImageRequestHandler(cgImage: image).perform([request])

        var lines: [Line] = []
        var candidates: [VNRecognizedText] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let rect = VisionGeometry.pixelRect(fromNormalized: observation.boundingBox, imageWidth: image.width, imageHeight: image.height)
            lines.append(Line(text: candidate.string, rect: rect))
            candidates.append(candidate)
        }
        return OCRPage(lines: lines, candidates: candidates, width: image.width, height: image.height)
    }

    /// Box for part of line `i`; falls back to the whole line if Vision can't box the substring.
    public func locate(_ kind: PIIKind, _ nsRange: NSRange, onLine i: Int) -> LocatedDetection? {
        guard lines.indices.contains(i) else { return nil }
        let text = lines[i].text
        guard let range = Range(nsRange, in: text) else { return nil }
        let normalized = (try? candidates[i].boundingBox(for: range))??.boundingBox
        let rect = normalized.map { VisionGeometry.pixelRect(fromNormalized: $0, imageWidth: width, imageHeight: height) }
            ?? lines[i].rect
        return LocatedDetection(kind: kind, text: String(text[range]), rect: rect)
    }

    /// Runs `pipeline` on each line plus form-label matching. With `labelNeighbors`, a standalone
    /// label's value is taken from the box to its right or below; without it, only same-line values count.
    public func detect(pipeline: DetectionPipeline, labelNeighbors: Bool = true) -> [LocatedDetection] {
        var located: [LocatedDetection] = []
        for i in lines.indices {
            for detection in pipeline.detect(in: lines[i].text) {
                if let d = locate(detection.kind, detection.range, onLine: i) { located.append(d) }
            }

            for label in FieldLabels.matches(in: lines[i].text) {
                if let value = label.valueRange {
                    if let d = locate(label.kind, value, onLine: i) { located.append(d) }
                    continue
                }
                guard labelNeighbors, let labelBox = locate(label.kind, label.labelRange, onLine: i) else { continue }
                let others = lines.indices.filter { $0 != i }
                guard let n = FieldLabels.neighbor(of: labelBox.rect, among: others.map { lines[$0].rect }) else { continue }
                let j = others[n]
                if let value = FieldLabels.valueRange(ofNeighbor: lines[j].text),
                   let d = locate(label.kind, value, onLine: j) {
                    located.append(d)
                }
            }
        }
        return located
    }
}

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
    /// The part of the image each candidate was read from, in pixels (the whole image, or a re-read crop).
    private let regions: [CGRect]

    private init(lines: [Line], candidates: [VNRecognizedText], regions: [CGRect]) {
        self.lines = lines
        self.candidates = candidates
        self.regions = regions
    }

    public static func recognize(_ image: CGImage) throws -> OCRPage {
        let whole = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        var lines: [Line] = []
        var candidates: [VNRecognizedText] = []
        var regions: [CGRect] = []
        for (candidate, rect) in try read(image) {
            lines.append(Line(text: candidate.string, rect: rect))
            candidates.append(candidate)
            regions.append(whole)
        }

        // Vision sometimes reads a line of small text as a squashed box of garbage
        // ("registered_address" → "neaistened addnecc", 6 px tall). Read those again on their own.
        let heights = lines.map(\.rect.height).sorted()
        if let median = heights.isEmpty ? nil : heights[heights.count / 2] {
            for i in lines.indices where lines[i].rect.height < 0.6 * median {
                let old = lines[i].rect
                let region = old.insetBy(dx: -median / 2, dy: -median).integral.intersection(whole)
                guard let crop = image.cropping(to: region) else { continue }
                let reread: [(VNRecognizedText, CGRect)] = try read(crop).map { ($0.0, $0.1.offsetBy(dx: region.minX, dy: region.minY)) }
                let sameLine = reread.filter { $0.1.height >= 0.6 * median && $0.1.intersects(old.insetBy(dx: 0, dy: -median / 2)) }
                guard let best = sameLine.min(by: { abs($0.1.midY - old.midY) < abs($1.1.midY - old.midY) }) else { continue }
                lines[i] = Line(text: best.0.string, rect: best.1)
                candidates[i] = best.0
                regions[i] = region
            }
        }
        return OCRPage(lines: lines, candidates: candidates, regions: regions)
    }

    /// Each recognized line's top candidate and its rect, in pixels of `image`.
    private static func read(_ image: CGImage) throws -> [(VNRecognizedText, CGRect)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction "fixes" emails and digit runs.
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0

        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map {
                ($0, VisionGeometry.pixelRect(fromNormalized: observation.boundingBox, imageWidth: image.width, imageHeight: image.height))
            }
        }
    }

    /// Box for part of line `i`; falls back to the whole line if Vision can't box the substring.
    public func locate(_ kind: PIIKind, _ nsRange: NSRange, onLine i: Int) -> LocatedDetection? {
        guard lines.indices.contains(i) else { return nil }
        let text = lines[i].text
        guard let range = Range(nsRange, in: text) else { return nil }
        let normalized = (try? candidates[i].boundingBox(for: range))??.boundingBox
        let region = regions[i]
        let rect = normalized.map {
            VisionGeometry.pixelRect(fromNormalized: $0, imageWidth: Int(region.width), imageHeight: Int(region.height))
                .offsetBy(dx: region.minX, dy: region.minY)
        } ?? lines[i].rect
        return LocatedDetection(kind: kind, text: String(text[range]), rect: rect)
    }

    /// Runs `pipeline` on each line plus form-label matching. With `labelNeighbors`, a standalone
    /// label's value is taken from the boxes to its right or below (`FieldLabels.valueBoxes`);
    /// without it, only same-line values count.
    public func detect(pipeline: DetectionPipeline, labelNeighbors: Bool = true) -> [LocatedDetection] {
        let neighbor: ((Int, FieldLabelMatch) -> [Int])? = labelNeighbors ? { i, label in
            guard let labelBox = self.locate(label.kind, label.labelRange, onLine: i) else { return [] }
            let others = self.lines.indices.filter { $0 != i }
            // An empty cell ("—") doesn't end the row; it just has nothing to redact.
            return FieldLabels.valueBoxes(of: labelBox.rect, among: others.map { self.lines[$0].rect }) {
                let text = self.lines[others[$0]].text
                return !text.contains(where: { $0.isLetter || $0.isNumber }) || FieldLabels.valueRange(ofNeighbor: text) != nil
            }.map { others[$0] }
        } : nil
        return LineRules.detect(lines: lines.map(\.text), pipeline: pipeline, neighbor: neighbor)
            .compactMap { locate($0.kind, $0.range, onLine: $0.line) }
    }
}

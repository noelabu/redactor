import Foundation

/// A detection on one OCR line of a page.
public struct LineDetection: Sendable, Equatable {
    public let line: Int
    public let range: NSRange
    public let kind: PIIKind

    public init(line: Int, range: NSRange, kind: PIIKind) {
        self.line = line
        self.range = range
        self.kind = kind
    }
}

public struct LinePIIResult: Sendable, Equatable {
    public let detections: [LineDetection]
    /// Lines the detector couldn't read (e.g. a language it doesn't support).
    public let skippedLines: Int

    public init(detections: [LineDetection], skippedLines: Int = 0) {
        self.detections = detections
        self.skippedLines = skippedLines
    }
}

/// A detector that reads the whole page of OCR lines at once (e.g. a language model).
/// It can only add boxes: the rule-based detectors run regardless of what it returns.
public protocol LinePIIDetector: Sendable {
    func detect(lines: [String]) async throws -> LinePIIResult
}

public struct LinePIIDetectorUnavailable: Error, Sendable {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
}

/// A value a model reported, before it is checked against the page.
public struct ReportedFinding: Sendable, Equatable {
    public let line: Int
    public let text: String
    public let kind: PIIKind

    public init(line: Int, text: String, kind: PIIKind) {
        self.line = line
        self.text = text
        self.kind = kind
    }
}

public enum FindingMatcher {
    /// Maps reported findings to exact ranges on the page. Text is matched case-insensitively on
    /// the reported line first, then on any line. Findings whose text isn't on the page are
    /// dropped, so a hallucinated value can never place a box.
    public static func match(_ findings: [ReportedFinding], lines: [String]) -> [LineDetection] {
        var result: [LineDetection] = []
        for finding in findings {
            let text = finding.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2 else { continue }
            let preferred = lines.indices.contains(finding.line) ? [finding.line] : []
            for candidates in [preferred, Array(lines.indices)] {
                let hits = candidates.flatMap { i in occurrences(of: text, in: lines[i]).map { LineDetection(line: i, range: $0, kind: finding.kind) } }
                if !hits.isEmpty {
                    result.append(contentsOf: hits)
                    break
                }
            }
        }
        return result
    }

    private static func occurrences(of needle: String, in haystack: String) -> [NSRange] {
        let ns = haystack as NSString
        var ranges: [NSRange] = []
        var search = NSRange(location: 0, length: ns.length)
        while true {
            let r = ns.range(of: needle, options: [.caseInsensitive], range: search)
            guard r.location != NSNotFound else { break }
            ranges.append(r)
            let next = NSMaxRange(r)
            search = NSRange(location: next, length: ns.length - next)
        }
        return ranges
    }
}

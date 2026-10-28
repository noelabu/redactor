import Foundation

public struct DetectionPipeline: Sendable {
    public let detectors: [any Detector]

    public static let standard = DetectionPipeline(detectors: [
        EmailDetector(), CreditCardDetector(), PhilippineIDDetector(), DataDetectorDetector(), SecretDetector(),
    ])

    /// For copied text: links stay readable so shared links (e.g. to a QA Studio document) still work.
    /// PII inside a link is still caught by the other detectors and by code keys (`?email=…`).
    public static let text = DetectionPipeline(detectors: [
        EmailDetector(), CreditCardDetector(), PhilippineIDDetector(), DataDetectorDetector(includeLinks: false), SecretDetector(),
    ])

    public init(detectors: [any Detector]) {
        self.detectors = detectors
    }

    public func detect(in text: String) -> [Detection] {
        Self.merge(detectors.flatMap { $0.detect(in: text) })
    }

    /// Merges overlapping ranges into their union.
    /// The earliest-starting detection's kind is kept; over-redacting is the safe direction.
    public static func merge(_ detections: [Detection]) -> [Detection] {
        let all = detections
            .filter { $0.range.length > 0 }
            .sorted { $0.range.location < $1.range.location }
        var merged: [Detection] = []
        for d in all {
            if let last = merged.last, NSMaxRange(last.range) > d.range.location {
                let union = NSUnionRange(last.range, d.range)
                merged[merged.count - 1] = Detection(kind: last.kind, range: union)
            } else {
                merged.append(d)
            }
        }
        return merged
    }
}

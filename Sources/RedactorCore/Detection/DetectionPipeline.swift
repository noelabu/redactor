import Foundation

public struct DetectionPipeline: Sendable {
    public let detectors: [any Detector]

    public static let standard = DetectionPipeline(detectors: [
        EmailDetector(), CreditCardDetector(), PhilippineIDDetector(), DataDetectorDetector(),
    ])

    public init(detectors: [any Detector]) {
        self.detectors = detectors
    }

    /// Runs every detector and merges overlapping ranges into their union.
    /// The earliest-starting detection's kind is kept; over-redacting is the safe direction.
    public func detect(in text: String) -> [Detection] {
        let all = detectors.flatMap { $0.detect(in: text) }
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

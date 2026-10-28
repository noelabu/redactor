import Foundation

/// The rule layer shared by screenshots and copied text: `pipeline` on each line, plus the values
/// of labelled fields and code keys.
public enum LineRules {
    /// For a standalone label, `neighbor` returns the lines holding its value (empty for none);
    /// pass nil to take only same-line values.
    public static func detect(
        lines: [String],
        pipeline: DetectionPipeline,
        neighbor: ((_ line: Int, _ label: FieldLabelMatch) -> [Int])?
    ) -> [LineDetection] {
        var found: [LineDetection] = []
        for i in lines.indices {
            for detection in pipeline.detect(in: lines[i]) {
                found.append(LineDetection(line: i, range: detection.range, kind: detection.kind))
            }

            for label in FieldLabels.matches(in: lines[i]) {
                if let value = label.valueRange {
                    found.append(LineDetection(line: i, range: value, kind: label.kind))
                    continue
                }
                guard let neighbor else { continue }
                for j in neighbor(i, label) where lines.indices.contains(j) {
                    guard let value = FieldLabels.valueRange(ofNeighbor: lines[j]) else { continue }
                    found.append(LineDetection(line: j, range: value, kind: label.kind))
                }
            }
        }
        return found + repeats(of: found, in: lines)
    }

    /// Other places the same value appears, e.g. a name shown both as extracted text and in an
    /// edit box. Matched case-insensitively; values under 3 characters are skipped.
    static func repeats(of found: [LineDetection], in lines: [String]) -> [LineDetection] {
        var seen: Set<String> = []
        var result: [LineDetection] = []
        for d in found {
            let value = (lines[d.line] as NSString).substring(with: d.range)
            guard value.count >= 3, seen.insert(value.lowercased()).inserted else { continue }
            for (i, line) in lines.enumerated() {
                let ns = line as NSString
                var search = NSRange(location: 0, length: ns.length)
                while case let r = ns.range(of: value, options: [.caseInsensitive], range: search), r.location != NSNotFound {
                    if !found.contains(where: { $0.line == i && NSIntersectionRange($0.range, r).length > 0 }) {
                        result.append(LineDetection(line: i, range: r, kind: d.kind))
                    }
                    search = NSRange(location: NSMaxRange(r), length: ns.length - NSMaxRange(r))
                }
            }
        }
        return result
    }
}

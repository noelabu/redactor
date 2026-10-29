import Foundation

public struct TextRedactionResult: Sendable, Equatable {
    /// The redacted text; equal to the input when nothing was found.
    public let text: String
    /// Values replaced with placeholders.
    public let replacements: Int
    public let aiStatus: AIStatus
    /// Replacements added by the double-check pass.
    public let addedByDoubleCheck: Int

    public var changed: Bool { replacements > 0 }
}

public enum TextRedactionError: Error, Equatable {
    /// The double-check still found PII after its last pass.
    case residualPII
}

/// Redacts copied text: the same rules and AI check as screenshots, with values replaced by
/// numbered placeholders (`[NAME 1]`) instead of boxes. Placeholders already in the text are left
/// alone, so redacting its own output changes nothing.
public enum TextRedactionEngine {
    /// Longer text skips the AI check; the rules still run.
    public static let aiCharacterLimit = 10_000
    /// A standalone label ("Address") takes the next non-blank line as its value only if that line
    /// is this short, so a heading in prose doesn't swallow the paragraph under it.
    static let maxNeighborValueLength = 80

    public static func run(
        _ text: String,
        pipeline: DetectionPipeline = .text,
        blockDetectors: [any Detector] = [PrivateKeyBlockDetector()],
        ai: (any LinePIIDetector)? = nil,
        doubleCheckPasses: Int = 2
    ) async throws -> TextRedactionResult {
        var numbering = PlaceholderNumbering(seededFrom: text)
        var found = rules(text, pipeline: pipeline, blockDetectors: blockDetectors, neighbors: true)

        var aiStatus = AIStatus.off
        if let ai, (text as NSString).length <= aiCharacterLimit {
            let lines = split(text)
            do {
                let result = try await ai.detect(lines: lines.map(\.text))
                found += result.detections.map { Detection(kind: $0.kind, range: NSRange(location: lines[$0.line].offset + $0.range.location, length: $0.range.length)) }
                aiStatus = .used(skippedLines: result.skippedLines)
            } catch let error as LinePIIDetectorUnavailable {
                aiStatus = .unavailable(error.reason)
            } catch {
                aiStatus = .failed(String(describing: error))
            }
        }

        let first = outsidePlaceholders(found, in: text)
        guard !first.isEmpty else {
            return TextRedactionResult(text: text, replacements: 0, aiStatus: aiStatus, addedByDoubleCheck: 0)
        }
        var out = Placeholders.apply(text, first, numbering: &numbering)

        // Double-check: the rules again on the output, without label neighbours (as for images).
        var added = 0
        for _ in 0..<doubleCheckPasses {
            let leftover = outsidePlaceholders(rules(out, pipeline: pipeline, blockDetectors: blockDetectors, neighbors: false), in: out)
            guard !leftover.isEmpty else { break }
            added += leftover.count
            out = Placeholders.apply(out, leftover, numbering: &numbering)
        }
        if !outsidePlaceholders(rules(out, pipeline: pipeline, blockDetectors: blockDetectors, neighbors: false), in: out).isEmpty {
            throw TextRedactionError.residualPII
        }
        return TextRedactionResult(text: out, replacements: first.count + added, aiStatus: aiStatus, addedByDoubleCheck: added)
    }

    /// Rule detections over the whole text, with placeholders masked so they never match.
    private static func rules(_ text: String, pipeline: DetectionPipeline, blockDetectors: [any Detector], neighbors: Bool) -> [Detection] {
        let masked = Placeholders.masked(text)
        let lines = split(masked)
        let neighbor: ((Int, FieldLabelMatch) -> [Int])? = neighbors ? { i, label in
            nextValueLine(after: i, for: label.kind, in: lines.map(\.text)).map { [$0] } ?? []
        } : nil
        let perLine = LineRules.detect(lines: lines.map(\.text), pipeline: pipeline, neighbor: neighbor).map {
            Detection(kind: $0.kind, range: NSRange(location: lines[$0.line].offset + $0.range.location, length: $0.range.length))
        }
        return perLine + blockDetectors.flatMap { $0.detect(in: masked) }
    }

    /// The next non-blank line within two, if it's short enough to be a field value (and has a
    /// digit, for kinds that are numbers or dates).
    private static func nextValueLine(after i: Int, for kind: PIIKind, in lines: [String]) -> Int? {
        guard let j = lines.indices.dropFirst(i + 1).prefix(2).first(where: { !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let line = lines[j].trimmingCharacters(in: .whitespaces)
        guard line.count <= maxNeighborValueLength else { return nil }
        if [.idNumber, .phone, .birthdate].contains(kind), !line.contains(where: \.isNumber) { return nil }
        return j
    }

    /// Detections with any part inside an existing placeholder cut away, merged.
    /// Pieces are trimmed to their first..last non-whitespace character and kept only if they hold a letter or digit.
    private static func outsidePlaceholders(_ detections: [Detection], in text: String) -> [Detection] {
        let ns = text as NSString
        let protected = Placeholders.ranges(in: text)
        var pieces: [Detection] = []
        for d in detections where d.range.length > 0 && NSMaxRange(d.range) <= ns.length {
            var remaining = [d.range]
            for p in protected {
                remaining = remaining.flatMap { r -> [NSRange] in
                    guard NSIntersectionRange(r, p).length > 0 else { return [r] }
                    return [
                        NSRange(location: r.location, length: max(0, p.location - r.location)),
                        NSRange(location: NSMaxRange(p), length: max(0, NSMaxRange(r) - NSMaxRange(p))),
                    ].filter { $0.length > 0 }
                }
            }
            for r in remaining {
                if let t = trimmed(r, in: ns) { pieces.append(Detection(kind: d.kind, range: t)) }
            }
        }
        return DetectionPipeline.merge(pieces)
    }

    private static func trimmed(_ range: NSRange, in ns: NSString) -> NSRange? {
        let piece = ns.substring(with: range)
        guard piece.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        let leading = piece.utf16.count - piece.drop(while: \.isWhitespace).utf16.count
        let trailing = piece.utf16.count - String(piece.reversed().drop(while: \.isWhitespace).reversed()).utf16.count
        return NSRange(location: range.location + leading, length: range.length - leading - trailing)
    }

    /// Lines without their terminators, with each line's UTF-16 offset in the text.
    static func split(_ text: String) -> [(text: String, offset: Int)] {
        let ns = text as NSString
        var lines: [(String, Int)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            lines.append((ns.substring(with: range), range.location))
        }
        return lines
    }
}

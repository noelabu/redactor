import CoreGraphics
import Foundation

/// A redaction rectangle in image pixels, top-left origin.
public struct RedactionBox: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var rect: CGRect
    public var kind: PIIKind
    public var enabled: Bool

    public init(id: UUID = UUID(), rect: CGRect, kind: PIIKind, enabled: Bool = true) {
        self.id = id
        self.rect = rect
        self.kind = kind
        self.enabled = enabled
    }
}

public enum BoxOps {
    /// Grows `rect` sideways by max(2px, 15% of its height) and vertically by max(1px, 5%),
    /// clamped to `bounds`. Vision's boxes already span the line height, so vertical padding
    /// stays small to avoid covering the lines above and below.
    public static func pad(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        let dx = max(2, rect.height * 0.15)
        let dy = max(1, rect.height * 0.05)
        return rect.insetBy(dx: -dx, dy: -dy).intersection(bounds).integral
    }

    /// Repeatedly merges boxes that intersect on the same line (vertical overlap at least 60%
    /// of the shorter box) until none remain. Boxes on different lines are never merged,
    /// so one rectangle never spans two rows. The first box's kind wins.
    public static func merge(_ boxes: [RedactionBox]) -> [RedactionBox] {
        func sameLine(_ a: CGRect, _ b: CGRect) -> Bool {
            let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
            return overlap >= 0.6 * min(a.height, b.height)
        }
        var result = boxes
        var changed = true
        while changed {
            changed = false
            outer: for i in result.indices {
                for j in result.indices where j > i {
                    if result[i].rect.intersects(result[j].rect), sameLine(result[i].rect, result[j].rect) {
                        result[i].rect = result[i].rect.union(result[j].rect)
                        result.remove(at: j)
                        changed = true
                        break outer
                    }
                }
            }
        }
        return result
    }
}

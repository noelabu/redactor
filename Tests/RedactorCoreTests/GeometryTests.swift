import CoreGraphics
import Foundation
import Testing
@testable import RedactorCore

@Suite struct VisionGeometryTests {
    @Test func flipsBottomLeftToTopLeft() {
        // Normalized rect in the bottom-left corner of a 200x100 image.
        let r = VisionGeometry.pixelRect(fromNormalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.2), imageWidth: 200, imageHeight: 100)
        #expect(r == CGRect(x: 0, y: 80, width: 100, height: 20))
    }

    @Test func topRightCorner() {
        let r = VisionGeometry.pixelRect(fromNormalized: CGRect(x: 0.75, y: 0.9, width: 0.25, height: 0.1), imageWidth: 400, imageHeight: 300)
        #expect(abs(r.minX - 300) < 0.001)
        #expect(abs(r.minY) < 0.001)
        #expect(abs(r.width - 100) < 0.001)
        #expect(abs(r.height - 30) < 0.001)
    }
}

@Suite struct BoxOpsTests {
    let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

    @Test func padsByMinimums() {
        #expect(BoxOps.pad(CGRect(x: 10, y: 10, width: 10, height: 4), in: bounds) == CGRect(x: 8, y: 9, width: 14, height: 6))
    }

    @Test func padsSidewaysMoreThanVertically() {
        // dx = 15% of 40 = 6, dy = 5% of 40 = 2
        #expect(BoxOps.pad(CGRect(x: 20, y: 20, width: 10, height: 40), in: bounds) == CGRect(x: 14, y: 18, width: 22, height: 44))
    }

    @Test func clampsToBounds() {
        #expect(BoxOps.pad(CGRect(x: 0, y: 95, width: 10, height: 5), in: bounds) == CGRect(x: 0, y: 94, width: 12, height: 6))
    }

    @Test func doesNotMergeAcrossLines() {
        // Two rows whose boxes touch by a few pixels, as on densely spaced documents.
        let boxes = [
            RedactionBox(rect: CGRect(x: 10, y: 0, width: 80, height: 34), kind: .address),
            RedactionBox(rect: CGRect(x: 40, y: 30, width: 50, height: 34), kind: .phone),
        ]
        #expect(BoxOps.merge(boxes).count == 2)
    }

    @Test func mergesTransitively() {
        let boxes = [
            RedactionBox(rect: CGRect(x: 0, y: 0, width: 10, height: 10), kind: .email),
            RedactionBox(rect: CGRect(x: 30, y: 0, width: 10, height: 10), kind: .phone),
            RedactionBox(rect: CGRect(x: 8, y: 0, width: 25, height: 10), kind: .link),
        ]
        let merged = BoxOps.merge(boxes)
        #expect(merged.count == 1)
        #expect(merged[0].rect == CGRect(x: 0, y: 0, width: 40, height: 10))
        #expect(merged[0].kind == .email)
    }

    @Test func leavesSeparateBoxesAlone() {
        let boxes = [
            RedactionBox(rect: CGRect(x: 0, y: 0, width: 10, height: 10), kind: .email),
            RedactionBox(rect: CGRect(x: 0, y: 50, width: 10, height: 10), kind: .phone),
        ]
        #expect(BoxOps.merge(boxes).count == 2)
    }
}

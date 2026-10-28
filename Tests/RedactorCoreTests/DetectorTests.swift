import Foundation
import Testing
@testable import RedactorCore

private func matched(_ text: String, _ detections: [Detection]) -> [String] {
    detections.map { (text as NSString).substring(with: $0.range) }
}

@Suite struct LuhnTests {
    @Test(arguments: ["4111111111111111", "378282246310005", "6011111111111117", "5555555555554444"])
    func validNumbers(_ n: String) { #expect(Luhn.isValid(n)) }

    @Test(arguments: ["4111111111111112", "378282246310006", "", "41111a1111111111"])
    func invalidNumbers(_ n: String) { #expect(!Luhn.isValid(n)) }
}

@Suite struct EmailDetectorTests {
    @Test func findsEmailInSentence() {
        let text = "Contact jane.doe+work@example.co.uk today"
        #expect(matched(text, EmailDetector().detect(in: text)) == ["jane.doe+work@example.co.uk"])
    }

    @Test func toleratesOCRSpaceAroundAt() {
        let text = "jane @ example.com"
        #expect(matched(text, EmailDetector().detect(in: text)) == ["jane @ example.com"])
    }

    @Test func ignoresPlainText() {
        #expect(EmailDetector().detect(in: "no address here @ all").isEmpty)
    }
}

@Suite struct CreditCardDetectorTests {
    @Test func findsSpacedAndDashedCards() {
        let text = "Card 4111 1111 1111 1111 and 5555-5555-5555-4444."
        #expect(matched(text, CreditCardDetector().detect(in: text)) == ["4111 1111 1111 1111", "5555-5555-5555-4444"])
    }

    @Test func rejectsFailedChecksum() {
        #expect(CreditCardDetector().detect(in: "Card 4111 1111 1111 1112").isEmpty)
    }

    @Test func rejectsShortDigitRuns() {
        #expect(CreditCardDetector().detect(in: "Order 123456789012").isEmpty)
    }
}

@Suite struct DataDetectorDetectorTests {
    @Test func findsPhone() {
        let text = "Call (415) 555-0132 now"
        let d = DataDetectorDetector().detect(in: text)
        #expect(d.map(\.kind) == [.phone])
        #expect(matched(text, d) == ["(415) 555-0132"])
    }

    @Test func findsLink() {
        let text = "See https://example.com/path"
        #expect(DataDetectorDetector().detect(in: text).map(\.kind) == [.link])
    }

    @Test func findsAddress() {
        let text = "Ship to 1 Infinite Loop, Cupertino, CA 95014"
        #expect(DataDetectorDetector().detect(in: text).map(\.kind).contains(.address))
    }
}

@Suite struct DetectionPipelineTests {
    struct Fixed: Detector {
        let detections: [Detection]
        func detect(in text: String) -> [Detection] { detections }
    }

    @Test func mergesOverlapsIntoUnion() {
        let p = DetectionPipeline(detectors: [
            Fixed(detections: [Detection(kind: .email, range: NSRange(location: 5, length: 10))]),
            Fixed(detections: [Detection(kind: .link, range: NSRange(location: 10, length: 10))]),
        ])
        #expect(p.detect(in: "") == [Detection(kind: .email, range: NSRange(location: 5, length: 15))])
    }

    @Test func keepsDisjointRanges() {
        let p = DetectionPipeline(detectors: [Fixed(detections: [
            Detection(kind: .phone, range: NSRange(location: 20, length: 3)),
            Detection(kind: .email, range: NSRange(location: 0, length: 5)),
        ])])
        #expect(p.detect(in: "").map(\.range.location) == [0, 20])
    }

    @Test func emailIsNotDoubleCountedAsMailtoLink() {
        let text = "jane.doe@example.com"
        #expect(DetectionPipeline.standard.detect(in: text).count == 1)
    }
}

import CoreGraphics
import Foundation
import Testing
@testable import RedactorCore

private func matched(_ text: String, _ ranges: [NSRange]) -> [String] {
    ranges.map { (text as NSString).substring(with: $0) }
}

@Suite struct PhilippineIDDetectorTests {
    @Test(arguments: [
        "123-456-789-000",      // TIN with branch code
        "123-456-789",          // TIN
        "123 456 789 00000",    // TIN, spaces, 5-digit branch
        "34-1234567-8",         // SSS
        "12-345678901-2",       // PhilHealth
        "1234-5678-9012",       // Pag-IBIG MID
        "1234 5678 9012 3456",  // PhilSys PSN
        "0111-1234567-8",       // UMID CRN
        "P1234567A",            // passport (new)
        "EB1234567",            // passport (old)
        "N01-23-456789",        // LTO licence
    ])
    func findsFormat(_ id: String) {
        let text = "No. \(id) issued"
        #expect(matched(text, PhilippineIDDetector().detect(in: text).map(\.range)).contains(id))
    }

    @Test(arguments: [
        "123456789",            // bare digits: label-only
        "123-456 789",          // mixed separators
        "2026-10-27",           // ISO date
        "v1.2.3",
        "P123456",              // too short for a passport
    ])
    func ignoresNonIDs(_ text: String) {
        #expect(PhilippineIDDetector().detect(in: text).isEmpty)
    }
}

@Suite struct FieldLabelTests {
    func values(_ line: String) -> [(PIIKind, String?)] {
        FieldLabels.matches(in: line).map { m in
            (m.kind, m.valueRange.map { (line as NSString).substring(with: $0) })
        }
    }

    @Test func sameLineValues() {
        #expect(values("Name: Juan Dela Cruz").map(\.1) == ["Juan Dela Cruz"])
        #expect(values("Date of Birth: 01/15/1990").map(\.0) == [.birthdate])
        #expect(values("Pangalan: Maria Clara P. Santos").map(\.1) == ["Maria Clara P. Santos"])
        #expect(values("Tirahan: 123 Rizal St., Brgy. San Antonio, Makati City").map(\.1) == ["123 Rizal St., Brgy. San Antonio, Makati City"])
    }

    @Test func splitsTwoLabelsOnOneLine() {
        let v = values("Name: Juan Dela Cruz   Date of Birth: 01/15/1990")
        #expect(v.map(\.0) == [.name, .birthdate])
        #expect(v.map(\.1) == ["Juan Dela Cruz", "01/15/1990"])
    }

    @Test func longerLabelWins() {
        let v = values("Mother’s Maiden Name: Reyes")
        #expect(v.count == 1)
        #expect(v.first?.1 == "Reyes")
        #expect(values("Account Name: Juan Dela Cruz").map(\.0) == [.name])
    }

    @Test func idLabelsWithoutColonOrSeparators() {
        #expect(values("TIN 123456789").map(\.1) == ["123456789"])
        #expect(values("SSS No. 3412345678").map(\.1) == ["3412345678"])
        #expect(values("PRC License No. 0123456").map(\.1) == ["0123456"])
        #expect(values("4. Voter's ID: 7603-0012A-K1234ABC").map(\.1) == ["7603-0012A-K1234ABC"])
    }

    @Test func standaloneLabelHasNoValue() {
        let v = values("Address")
        #expect(v.count == 1)
        #expect(v.first?.0 == .address)
        #expect(v.first?.1 == nil)
        #expect(values("Date of Birth:").first?.1 == nil)
    }

    @Test(arguments: [
        "Contact us at the front desk",
        "Mid-year review",
        "Username: noela",
        "Filename: report.pdf",
        "The name field is optional",
        "Identity verified",
    ])
    func ignoresProse(_ line: String) {
        #expect(values(line).isEmpty)
    }

    @Test func neighborValueRange() {
        #expect(FieldLabels.valueRange(ofNeighbor: "Juan Dela Cruz") == NSRange(location: 0, length: 14))
        #expect(FieldLabels.valueRange(ofNeighbor: "Juan Dela Cruz   TIN: 123") == NSRange(location: 0, length: 14))
        #expect(FieldLabels.valueRange(ofNeighbor: "Address") == nil)
        #expect(FieldLabels.valueRange(ofNeighbor: "5. Address:") == nil)
    }
}

@Suite struct FieldNeighborTests {
    let label = CGRect(x: 100, y: 100, width: 80, height: 20)

    @Test func prefersNearestBoxToTheRight() {
        let candidates = [
            CGRect(x: 100, y: 130, width: 200, height: 20),  // below
            CGRect(x: 400, y: 102, width: 100, height: 20),  // far right
            CGRect(x: 220, y: 98, width: 150, height: 20),   // near right
        ]
        #expect(FieldLabels.neighbor(of: label, among: candidates) == 2)
    }

    @Test func fallsBackToBelow() {
        let candidates = [
            CGRect(x: 100, y: 200, width: 200, height: 20),  // too far below
            CGRect(x: 105, y: 128, width: 200, height: 20),  // just below
        ]
        #expect(FieldLabels.neighbor(of: label, among: candidates) == 1)
    }

    @Test func ignoresBoxesElsewhere() {
        let candidates = [
            CGRect(x: 0, y: 0, width: 50, height: 20),       // above-left
            CGRect(x: 600, y: 130, width: 50, height: 20),   // below but far right
            CGRect(x: 10, y: 100, width: 50, height: 20),    // left on the same row
        ]
        #expect(FieldLabels.neighbor(of: label, among: candidates) == nil)
    }
}

/// Real Vision OCR over a rendered Philippine-style form.
@Suite struct PhilippineFormEndToEndTests {
    @Test func redactsLabelledFieldsAndIDs() async throws {
        let rows: [[String]] = [
            ["Name: Juan Dela Cruz"],
            ["Date of Birth: 01/15/1990"],
            ["TIN 123456789"],
            ["SSS No. 34-1234567-8"],
            ["PhilHealth 12-345678901-2"],
            ["Address"],
            ["123 Rizal St., Brgy. San Antonio, Makati City"],
            ["Pangalan", "Maria Santos"],
            ["Issued at Quezon City"],
        ]
        let pii = ["Juan Dela Cruz", "01/15/1990", "123456789", "34-1234567-8", "12-345678901-2",
                   "123 Rizal St., Brgy. San Antonio, Makati City", "Maria Santos"]
        let rendered = TestImages.form(rows, mark: pii + ["Issued at Quezon City", "Pangalan"], fontSize: 24, columnWidth: 260)
        let result = try await RedactionEngine.run(SourceImage(cgImage: rendered.image, dpi: 144))
        let out = try SourceImage(pngData: result.redactedPNG).cgImage

        for text in pii {
            let rect = try #require(rendered.rects[text])
            #expect(coverage(of: rect, by: result.boxes) >= 0.8, "\(text) mostly uncovered")
            #expect(leakedInk(in: rect, of: out) < 0.005, "\(text) still visible")
        }
        #expect(coverage(of: rendered.rects["Issued at Quezon City"]!, by: result.boxes) == 0)
        #expect(coverage(of: rendered.rects["Pangalan"]!, by: result.boxes) < 0.5)
    }
}

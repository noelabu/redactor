import Foundation
import Testing
@testable import RedactorCore

@Suite struct AIFindingFilterTests {
    // 2026-10-27
    let now = Date(timeIntervalSince1970: 1_793_122_930)

    @Test(arguments: [
        ("Juan Dela Cruz", PIIKind.name), ("Maria Santos", .name), ("Pedro Reyes", .name), ("MARIA CLARA SANTOS", .name),
        ("15 January 1990", .birthdate), ("JANUARY 15, 1990", .birthdate), ("01/15/90", .birthdate),
        ("0012-3456-78", .idNumber), ("P1234567A", .idNumber), ("09171234567", .phone),
        ("juan@gmail.com", .email), ("123 Rizal St., Brgy. San Antonio, Makati City", .address),
    ])
    func acceptsRealValues(_ value: String, _ kind: PIIKind) {
        #expect(AIFindingFilter.accept(value, as: kind, now: now))
    }

    @Test(arguments: [
        ("Quarterly Revenue Report", PIIKind.name), ("Prepared by Finance Team", .name), ("Q3 2026 revenue grew 12%", .name),
        ("Oct 3", .birthdate), ("Oct 20, 2026", .birthdate), ("October 2026", .birthdate),
        ("25000.00", .idNumber), ("25,000.00", .idNumber), ("BDO", .phone), ("12%", .idNumber),
        ("Oct 3", .email), ("Payslip for October 2026", .address),
    ])
    func rejectsNoise(_ value: String, _ kind: PIIKind) {
        #expect(!AIFindingFilter.accept(value, as: kind, now: now))
    }
}

@Suite struct BilingualLabelTests {
    @Test(arguments: [
        ("Apelyido / Last Name", PIIKind.name), ("Mga Pangalan / Given Names", .name),
        ("Petsa ng Kapanganakan / Date of Birth", .birthdate), ("Tirahan / Address", .address),
    ])
    func standaloneBilingualLabel(_ line: String, _ kind: PIIKind) {
        let m = FieldLabels.matches(in: line)
        #expect(m.count == 1)
        #expect(m.first?.kind == kind)
        #expect(m.first?.valueRange == nil)
        #expect(FieldLabels.valueRange(ofNeighbor: line) == nil)
    }

    @Test func slashedNonLabelsAreNotLabels() {
        #expect(FieldLabels.matches(in: "Sales / Marketing").isEmpty)
        #expect(FieldLabels.matches(in: "Approved / Rejected").isEmpty)
    }

    @Test func idCardEndToEnd() async throws {
        let rows: [[String]] = [
            ["Apelyido / Last Name"], ["SANTOS"],
            ["Mga Pangalan / Given Names"], ["MARIA CLARA"],
            ["Petsa ng Kapanganakan / Date of Birth"], ["JANUARY 15, 1990"],
        ]
        let pii = ["SANTOS", "MARIA CLARA", "JANUARY 15, 1990"]
        let rendered = TestImages.form(rows, mark: pii + ["Last Name"], fontSize: 22)
        let result = try await RedactionEngine.run(SourceImage(cgImage: rendered.image))
        let out = try SourceImage(pngData: result.redactedPNG).cgImage
        for text in pii {
            #expect(leakedInk(in: rendered.rects[text]!, of: out) < 0.005, "\(text) still visible")
        }
        #expect(coverage(of: rendered.rects["Last Name"]!, by: result.boxes) == 0)
    }
}

@Suite struct FilipinoTextTests {
    @Test func flagsFilipinoLines() {
        #expect(FilipinoText.isLikely("Hi po, ito po yung details ko"))
        #expect(FilipinoText.isLikely("Account sa GCash: 0917-123-4567"))
        #expect(FilipinoText.isLikely("Petsa ng Kapanganakan / Date of Birth"))
    }

    @Test func leavesEnglishLines() {
        #expect(!FilipinoText.isLikely("Pedro Reyes, 09171234567"))
        #expect(!FilipinoText.isLikely("Payslip for October 2026"))
        #expect(!FilipinoText.isLikely("SANTOS"))
    }
}

/// Runs Apple's real on-device model. Opt-in: REDACTOR_AI_EVAL=1 swift test --filter AIEvalTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["REDACTOR_AI_EVAL"] != nil && FoundationModelsDetector.unavailableReason == nil))
struct AIEvalTests {
    static let cases: [(lines: [String], expect: [String], mustNot: [String])] = [
        (["Payslip for October 2026", "Employee: Juan Dela Cruz", "Prepared by Maria Santos on Oct 3",
          "Born 15 January 1990 in Cebu City", "Basic pay 25,000.00", "Bank acct 0012-3456-78 BDO"],
         ["Juan Dela Cruz", "Maria Santos", "15 January 1990", "0012-3456-78"],
         ["Payslip", "25,000.00", "BDO", "October 2026"]),
        (["REPUBLIKA NG PILIPINAS", "Philippine Identification Card", "Apelyido / Last Name", "SANTOS",
          "Mga Pangalan / Given Names", "MARIA CLARA", "Petsa ng Kapanganakan / Date of Birth", "JANUARY 15, 1990",
          "Tirahan / Address", "123 RIZAL ST BRGY SAN ANTONIO MAKATI CITY"],
         ["MARIA CLARA", "JANUARY 15, 1990", "123 RIZAL ST BRGY SAN ANTONIO MAKATI CITY"],
         ["REPUBLIKA", "Philippine Identification Card", "Last Name", "Date of Birth"]),
        (["Hi po, ito po yung details ko", "Pedro Reyes, 09171234567", "Account sa GCash: 0917-123-4567",
          "Thanks! Meeting at 3pm sa Ortigas office", "Software Engineer, Acme Corp"],
         ["Pedro Reyes", "09171234567"],
         ["Meeting", "Ortigas office", "Software Engineer", "Acme Corp", "3pm"]),
        (["Quarterly Revenue Report", "Q3 2026 revenue grew 12% to PHP 4.2M", "Prepared by Finance Team", "Approved: Oct 20, 2026"],
         [], ["Quarterly", "4.2M", "Finance Team", "Oct 20, 2026"]),
    ]

    @Test func recallAndFalseHits() async throws {
        var hits = 0, expected = 0, falseHits = 0, skipped = 0
        for c in Self.cases {
            let start = Date()
            let result = try await FoundationModelsDetector().detect(lines: c.lines)
            let found = result.detections.map { (c.lines[$0.line] as NSString).substring(with: $0.range) }
            skipped += result.skippedLines
            print(String(format: "AIEVAL %.1fs skipped=%d found=%@", Date().timeIntervalSince(start), result.skippedLines, found.description))
            for e in c.expect {
                expected += 1
                if found.contains(where: { $0.localizedCaseInsensitiveContains(e) }) { hits += 1 } else { print("AIEVAL MISS \(e)") }
            }
            for m in c.mustNot where found.contains(where: { $0.localizedCaseInsensitiveContains(m) }) {
                falseHits += 1
                print("AIEVAL FALSE \(m)")
            }
        }
        print("AIEVAL recall \(hits)/\(expected), false hits \(falseHits), skipped lines \(skipped)")
        #expect(falseHits == 0)
    }
}

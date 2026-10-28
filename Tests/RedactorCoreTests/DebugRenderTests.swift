import Foundation
import Testing
@testable import RedactorCore

@Suite struct DebugRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["REDACTOR_DEBUG_OUT"] != nil))
    func writeDenseFormRender() async throws {
        let rows: [[String]] = [
            ["EMPLOYEE INFORMATION SHEET"],
            ["Name: Juan Dela Cruz", "Date of Birth: 01/15/1990"],
            ["TIN: 123-456-789-000", "SSS No.: 34-1234567-8"],
            ["PhilHealth: 12-345678901-2", "Pag-IBIG: 1234-5678-9012"],
            ["Address: 123 Rizal St., Brgy. San Antonio, Makati City"],
            ["Mobile: 0917 123 4567", "Email: juan.delacruz@gmail.com"],
            ["Position: Software Engineer", "Department: Engineering"],
            ["Mother's Maiden Name: Reyes", "Civil Status: Single"],
        ]
        let rendered = TestImages.form(rows, mark: [], fontSize: 13, columnWidth: 330, lineSpacing: 1.35)
        let result = try await RedactionEngine.run(SourceImage(cgImage: rendered.image, dpi: 144))
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["REDACTOR_DEBUG_OUT"]!)
        try ImageRedactor.pngData(rendered.image, dpi: 144).write(to: dir.appendingPathComponent("original.png"))
        try result.redactedPNG.write(to: dir.appendingPathComponent("redacted.png"))
        for b in result.boxes { print("BOX", b.kind, b.rect) }
    }
}

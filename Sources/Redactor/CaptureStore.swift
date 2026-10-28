import Foundation
import RedactorCore

/// An unredacted capture held in memory so the preview can un-redact boxes. Never written to disk.
struct StoredCapture: Identifiable {
    let id: UUID
    let originalPNG: Data
    var boxes: [RedactionBox]
    /// Set the first time the user clicks Save; later saves overwrite the same file.
    var outputURL: URL?
}

@MainActor
final class CaptureStore {
    private(set) var captures: [StoredCapture] = []
    let limit = 5

    var latest: StoredCapture? { captures.last }

    func add(_ capture: StoredCapture) {
        captures.append(capture)
        if captures.count > limit {
            captures.removeFirst(captures.count - limit)
        }
    }

    func capture(id: UUID) -> StoredCapture? {
        captures.first { $0.id == id }
    }

    func updateBoxes(id: UUID, _ boxes: [RedactionBox], outputURL: URL) {
        guard let i = captures.firstIndex(where: { $0.id == id }) else { return }
        captures[i].boxes = boxes
        captures[i].outputURL = outputURL
    }
}

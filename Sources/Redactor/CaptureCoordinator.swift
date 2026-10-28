import AppKit
import Foundation
import Observation
import RedactorCore

/// Hotkey → screencapture → OCR + redact → save + clipboard → notify.
/// The unredacted image only exists in a private temp file for the moment it takes to read it.
@MainActor
@Observable
final class CaptureCoordinator {
    private(set) var isCapturing = false
    /// True from the end of the selection until the redacted file is saved.
    private(set) var isProcessing = false
    private(set) var hasScreenPermission = CGPreflightScreenCaptureAccess()
    private(set) var hasCaptures = false
    var hotKeyAvailable = true

    @ObservationIgnored let store = CaptureStore()
    @ObservationIgnored let notifier = Notifier()
    @ObservationIgnored private let preview = PreviewWindowController()

    func refreshPermission() {
        hasScreenPermission = CGPreflightScreenCaptureAccess()
    }

    func openScreenRecordingSettings() {
        CGRequestScreenCaptureAccess()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    func capture() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        refreshPermission()
        guard hasScreenPermission else {
            CGRequestScreenCaptureAccess()
            notifier.post("Screen Recording permission is needed. Grant it from the Redactor menu.")
            return
        }

        // Loads the AI model while the user is still selecting.
        Task.detached(priority: .utility) { FoundationModelsDetector.prewarm() }

        let pasteboard = NSPasteboard.general
        let changeCountBefore = pasteboard.changeCount
        guard let originalPNG = await runScreencapture() else {
            // Holding Control during selection sends the unredacted image to the clipboard instead.
            if pasteboard.changeCount != changeCountBefore,
               pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.png.rawValue, NSPasteboard.PasteboardType.tiff.rawValue]) {
                pasteboard.clearContents()
                notifier.post("Unredacted capture removed from the clipboard. Don't hold Control while selecting.")
            }
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        guard let source = try? SourceImage(pngData: originalPNG) else {
            notifier.post("Redaction failed — nothing saved")
            return
        }

        // Show the capture straight away; boxes fill in when detection finishes.
        let id = UUID()
        let model = preview.show(title: "Detecting…", source: source, boxes: [], isLoading: true) { [weak self] boxes in
            self?.save(id: id, boxes: boxes) ?? false
        }

        let report: @Sendable (RedactionProgress) -> Void = { progress in
            Task { @MainActor in
                guard model.isLoading else { return }
                switch progress {
                case .rulesDone(let boxes):
                    model.boxes = boxes
                    model.stage = "Checking with AI…"
                case .aiChecking:
                    model.stage = "Checking with AI…"
                case .doubleChecking:
                    model.stage = "Double-checking…"
                }
            }
        }

        let result: RedactionResult
        do {
            result = try await Task.detached(priority: .userInitiated) {
                try await RedactionEngine.run(source, ai: FoundationModelsDetector(), progress: report)
            }.value
        } catch {
            preview.close(model)
            notifier.post("Redaction failed — nothing saved")
            return
        }

        // Only the clipboard gets the result; a file is written when the user clicks Save.
        copyToPasteboard(result.redactedPNG)

        store.add(StoredCapture(id: id, originalPNG: originalPNG, boxes: result.boxes))
        hasCaptures = true

        model.boxes = result.boxes
        model.status = Self.statusText(result)
        model.isLoading = false
        preview.finishLoading(model)
        preview.setTitle("Copied to clipboard", for: model)
    }

    func openPreview(id: UUID) {
        guard let capture = store.capture(id: id) else {
            notifier.post("Capture no longer in memory")
            return
        }
        guard let source = try? SourceImage(pngData: capture.originalPNG) else { return }
        preview.show(title: capture.outputURL?.lastPathComponent ?? "Not saved", source: source, boxes: capture.boxes) { [weak self] boxes in
            self?.save(id: id, boxes: boxes) ?? false
        }
    }

    private static func statusText(_ result: RedactionResult) -> String {
        let ai: String
        switch result.aiStatus {
        case .used(0): ai = "AI check on"
        case .used(let skipped): ai = "AI check on (\(skipped) Filipino line\(skipped == 1 ? "" : "s") skipped)"
        case .off: ai = "AI check off"
        case .unavailable(let reason): ai = "AI check off (\(reason))"
        case .failed: ai = "AI check failed"
        }
        let extra = result.boxesAddedByDoubleCheck
        return extra == 0 ? ai : "\(ai) · double-check added \(extra)"
    }

    func openLatestPreview() {
        guard let latest = store.latest else { return }
        openPreview(id: latest.id)
    }

    /// Re-renders from the in-memory original, writes it to the screenshot folder (overwriting
    /// this capture's file if it was saved before) and copies it. Returns false on failure.
    private func save(id: UUID, boxes: [RedactionBox]) -> Bool {
        guard let capture = store.capture(id: id) else {
            notifier.post("Capture no longer in memory")
            return false
        }
        do {
            let png = try RedactionEngine.render(SourceImage(pngData: capture.originalPNG), boxes: boxes)
            let url = capture.outputURL ?? ScreenshotNaming.fileURL(in: ScreenshotNaming.outputDirectory())
            try png.write(to: url, options: .atomic)
            copyToPasteboard(png)
            store.updateBoxes(id: id, boxes, outputURL: url)
            return true
        } catch {
            notifier.post("Save failed — nothing written")
            return false
        }
    }

    private func copyToPasteboard(_ png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    /// Interactive region capture into a private temp file. Returns the PNG bytes, or nil if cancelled.
    /// The temp file is deleted before returning on every path, and its absence is confirmed.
    private func runScreencapture() async -> Data? {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("redactor-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: tmp)
            if FileManager.default.fileExists(atPath: tmp.path) {
                notifier.post("Couldn't delete the unredacted temp capture at \(tmp.path). Delete it manually.")
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", "-x", "-t", "png", tmp.path]
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume()
            }
        }

        // Esc leaves no file; don't rely on the exit status.
        guard let data = try? Data(contentsOf: tmp), !data.isEmpty else { return nil }
        return data
    }

    /// Removes temp files left behind by a crash mid-capture.
    static func sweepTempFiles() {
        let dir = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names where name.hasPrefix("redactor-") && name.hasSuffix(".png") {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}

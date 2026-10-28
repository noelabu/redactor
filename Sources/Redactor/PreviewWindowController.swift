import AppKit
import RedactorCore
import SwiftUI

@MainActor
final class PreviewWindowController {
    private var window: NSWindow?
    private var model: PreviewModel?

    /// Shows `source` with `boxes` and returns the model so the caller can fill in boxes
    /// once detection finishes. `onSave` returns true when the save succeeded, which closes the window.
    @discardableResult
    func show(title: String, source: SourceImage, boxes: [RedactionBox], isLoading: Bool = false,
              onSave: @escaping ([RedactionBox]) -> Bool) -> PreviewModel {
        window?.close()

        let model = PreviewModel(image: source.cgImage, boxes: boxes, isLoading: isLoading)
        let view = PreviewView(
            model: model,
            onCancel: { [weak self] in self?.window?.close() },
            onSave: { [weak self] in
                if onSave(model.boxes) { self?.window?.close() }
            }
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.windowSize(for: source)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        self.window = window
        self.model = model

        // Redactor is a menu bar app, so a plain activate can leave the window behind the
        // frontmost app. Float it while detection runs so the progress is visible.
        if isLoading { window.level = .floating }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        return model
    }

    func finishLoading(_ model: PreviewModel) {
        guard model === self.model else { return }
        window?.level = .normal
    }

    /// Retitles the window only if it still shows `model` (another preview may have replaced it).
    func setTitle(_ title: String, for model: PreviewModel) {
        guard model === self.model else { return }
        window?.title = title
    }

    func close(_ model: PreviewModel) {
        guard model === self.model else { return }
        window?.close()
    }

    /// The image at its point size, capped to 80% of the screen, plus room for the bottom bar.
    private static func windowSize(for source: SourceImage) -> NSSize {
        let pointsPerPixel = 72 / max(source.dpi, 72)
        let imageSize = NSSize(
            width: CGFloat(source.cgImage.width) * pointsPerPixel,
            height: CGFloat(source.cgImage.height) * pointsPerPixel
        )
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let barHeight: CGFloat = 52
        let maxW = visible.width * 0.8, maxH = visible.height * 0.8 - barHeight
        let scale = min(1, maxW / imageSize.width, maxH / imageSize.height)
        return NSSize(
            width: max(420, imageSize.width * scale),
            height: max(200, imageSize.height * scale) + barHeight
        )
    }
}

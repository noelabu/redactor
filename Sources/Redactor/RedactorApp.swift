import SwiftUI

@main
struct RedactorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(coordinator: appDelegate.coordinator, clipboard: appDelegate.clipboard)
        } label: {
            Image(systemName: appDelegate.coordinator.isProcessing || appDelegate.clipboard.isWorking ? "hourglass" : "eye.slash")
        }
    }
}

private struct MenuContent: View {
    let coordinator: CaptureCoordinator
    @Bindable var clipboard: ClipboardGuard

    var body: some View {
        Button("Capture & Redact") {
            Task { await coordinator.capture() }
        }
        .keyboardShortcut("4", modifiers: [.command, .option, .shift])
        .disabled(coordinator.isCapturing)

        Button("Review Last Capture…") {
            coordinator.openLatestPreview()
        }
        .disabled(!coordinator.hasCaptures)

        Divider()
        Toggle("Redact Copied Text", isOn: $clipboard.isEnabled)

        Button("Restore Last Copy") {
            clipboard.restore()
        }
        .disabled(!clipboard.hasRestorable)

        if let app = clipboard.lastExternalApp, !clipboard.excludedBundleIDs.contains(app.bundleID) {
            Button("Exclude \(app.name)") {
                clipboard.exclude(app.bundleID)
            }
        }
        if !clipboard.excludedBundleIDs.isEmpty {
            Menu("Excluded Apps") {
                ForEach(clipboard.excludedBundleIDs, id: \.self) { id in
                    Button("Remove \(ClipboardGuard.appName(for: id))") {
                        clipboard.include(id)
                    }
                }
            }
        }

        if !coordinator.hasScreenPermission {
            Divider()
            Button("Grant Screen Recording…") {
                coordinator.openScreenRecordingSettings()
            }
        }
        if !coordinator.hotKeyAvailable {
            Divider()
            Text("Hotkey unavailable")
        }

        Divider()
        Button("Quit Redactor") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

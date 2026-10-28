import SwiftUI

@main
struct RedactorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(coordinator: appDelegate.coordinator)
        } label: {
            Image(systemName: appDelegate.coordinator.isProcessing ? "hourglass" : "eye.slash")
        }
    }
}

private struct MenuContent: View {
    let coordinator: CaptureCoordinator

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

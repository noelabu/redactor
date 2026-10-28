import AppKit
import Carbon.HIToolbox
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let coordinator = CaptureCoordinator()
    private(set) var hotKey: HotKey?

    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        CaptureCoordinator.sweepTempFiles()
        coordinator.notifier.requestAuthorization()
        hotKey = HotKey(keyCode: kVK_ANSI_4, modifiers: cmdKey | optionKey | shiftKey) { [coordinator] in
            Task { await coordinator.capture() }
        }
        coordinator.hotKeyAvailable = hotKey != nil
        if !coordinator.hasScreenPermission {
            // Makes Redactor appear in System Settings > Screen Recording.
            CGRequestScreenCaptureAccess()
        }
    }

    // Show error banners even while Redactor is the active app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

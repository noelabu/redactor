import AppKit
import Carbon.HIToolbox
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let coordinator = CaptureCoordinator()
    lazy var clipboard = ClipboardGuard(notifier: coordinator.notifier)
    private(set) var hotKey: HotKey?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let restore = UNNotificationAction(identifier: ClipboardGuard.restoreAction, title: "Restore original")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: ClipboardGuard.category, actions: [restore], intentIdentifiers: []),
        ])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        CaptureCoordinator.sweepTempFiles()
        coordinator.notifier.requestAuthorization()
        clipboard.start()
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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == ClipboardGuard.restoreAction else { return }
        let token = response.notification.request.content.userInfo["token"] as? Int
        await MainActor.run { clipboard.restore(token: token) }
    }
}

import Foundation
import UserNotifications

@MainActor
final class Notifier {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// A fixed `identifier` replaces the previous banner with that identifier.
    func post(
        title: String = "Redactor",
        _ body: String,
        identifier: String = UUID().uuidString,
        category: String? = nil,
        userInfo: [String: Int] = [:]
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let category { content.categoryIdentifier = category }
        content.userInfo = userInfo
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func remove(identifier: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
